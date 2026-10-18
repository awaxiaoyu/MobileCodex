import { Bridge } from './bridge.ts';
import { createHttpServer } from './http.ts';
import { AppServerBackend } from './app-server.ts';
import { DesktopToolsBackend } from './desktop-tools.ts';
import { RendererBackend } from './renderer-backend.ts';
import { FridaBackend } from './frida-backend.ts';
import { DeviceStore } from './devices.ts';
import { createMobileServer } from './mobile-server.ts';
import { discoverDesktop, findCodexExecutable } from './discovery.ts';
import { randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import QRCode from 'qrcode';

const args = process.argv.slice(2);
const command = args[0] ?? 'serve';
const option = (name: string) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
if (command === 'discover') { console.log(JSON.stringify(await discoverDesktop(), null, 2)); process.exit(0); }
if (command !== 'serve') throw new Error('Usage: node src/cli.ts discover|serve [--port N] [--standalone] [--workspace PATH] [--frida] [--pid PID] [--public-url wss://host/ws]');
if (args.includes('--frida') && option('--cdp')) throw new Error('Select one shared adapter: --frida or --cdp');

const workspace = option('--workspace') ?? process.env.MOBILE_CODEX_WORKSPACE ?? process.cwd();
const adminPort = Number(option('--port') ?? process.env.MOBILE_CODEX_PORT ?? 37841);
const bridge = new Bridge({ workspace });
let toolsBackend: DesktopToolsBackend | undefined;
let mobile: ReturnType<typeof createMobileServer> | undefined;
let server: ReturnType<typeof createHttpServer> | undefined;
const uiSession = randomBytes(32).toString('base64url');
const uiSessionExpiresAt = Date.now() + 30 * 60 * 1000;
let uiStatus: (() => Record<string, unknown>) | undefined;
let devices: DeviceStore | undefined;
let fridaBackend: FridaBackend | undefined;
const pairUrl = option('--public-url') ?? option('--pair-url') ?? process.env.MOBILE_CODEX_PUBLIC_URL ?? process.env.MOBILE_CODEX_PAIR_URL;
const mobileUrl = () => pairUrl ?? `wss://${option('--mobile-bind') ?? '0.0.0.0'}:${Number(option('--mobile-port') ?? 37842)}/ws`;
async function pairingPayload() {
  const value: Record<string, any> = { ...(devices?.beginPairing() ?? {}) };
  if (mobile) {
    value.url = mobileUrl();
    value.fingerprint = mobile.fingerprint;
  }
  if (value.id && value.secret && value.url && value.fingerprint) {
    // The QR contains the same short-lived JSON accepted by the mobile app.
    // It is returned only through the local, short-lived Desktop settings IPC.
    value.qr = await QRCode.toDataURL(JSON.stringify({ url: value.url, fingerprint: value.fingerprint, id: value.id, secret: value.secret, expiresAt: value.expiresAt }), { errorCorrectionLevel: 'M', margin: 2, width: 280 });
  }
  return value;
}
try {
if (args.includes('--standalone')) {
  const commandPath = await findCodexExecutable(option('--codex'));
  const standalone = new AppServerBackend({ command: commandPath, workspace: resolve(workspace) });
  await bridge.addBackend(standalone);
}
if (option('--cdp')) {
  if (!option('--target')) throw new Error('--cdp requires a selected --target ID');
  await bridge.addBackend(new RendererBackend({ endpoint: option('--cdp')!, targetId: option('--target')!, allowControl: args.includes('--allow-control') }));
}
if (args.includes('--frida')) {
  const pid = option('--pid');
  const discovered = pid ? undefined : await discoverDesktop();
  const desktopPid = pid ? Number(pid) : (discovered as any).desktop?.[0]?.ProcessId;
  if (!Number.isInteger(desktopPid) || desktopPid < 1) throw new Error('--frida could not find a Desktop Main PID; pass --pid PID');
  fridaBackend = new FridaBackend({ workspace: resolve(workspace), pid: desktopPid, python: process.env.MOBILE_CODEX_FRIDA_PYTHON, deps: process.env.MOBILE_CODEX_FRIDA_DEPS, allowControl: args.includes('--allow-control'), settingsUi: { endpoint: `http://127.0.0.1:${adminPort}`, token: uiSession }, projectProvider: async () => toolsBackend ? await toolsBackend.call('bridge.project.list', {}) : { projects: [] }, threadProvider: async (params) => toolsBackend ? await toolsBackend.call('bridge.thread.list', params ?? {}) : { threads: [] }, settingsRequest: async (action, payload) => {
    if (action === 'status') return uiStatus?.() ?? bridge.uiStatus();
    if (action === 'pairing') return await pairingPayload();
    if (action === 'revoke') { if (!devices || typeof payload.deviceId !== 'string') throw new Error('deviceId is required'); await devices.revoke(payload.deviceId); return { revoked: true }; }
    if (action === 'feature') {
      if (typeof payload.name !== 'string' || typeof payload.enabled !== 'boolean') throw new Error('Feature name and enabled state are required');
      if (payload.name === 'event-stream') { bridge.setEventStreamEnabled(payload.enabled); return uiStatus?.() ?? bridge.uiStatus(); }
      if (!fridaBackend) throw new Error('Desktop shared backend is unavailable');
      await fridaBackend.setFeature(payload.name, payload.enabled);
      return uiStatus?.() ?? bridge.uiStatus();
    }
    throw new Error('Unsupported Desktop settings action');
  } });
  await bridge.addBackend(fridaBackend);
}
if (process.env.CODEX_APP_TOOLS_PIPE_PATH && process.env.CODEX_THREAD_ID) {
  // This is a tools-only backend. It is never labelled desktop-shared and does
  // not pretend to control the Desktop live turn.
  toolsBackend = new DesktopToolsBackend({ pipePath: process.env.CODEX_APP_TOOLS_PIPE_PATH, threadId: process.env.CODEX_THREAD_ID, turnId: process.env.MOBILE_CODEX_TURN_ID ?? 'bridge-readonly-probe', hostId: process.env.CODEX_APP_TOOLS_CALLER_HOST_ID });
  await bridge.addBackend(toolsBackend);
}
const token = process.env.MOBILE_CODEX_LOCAL_TOKEN ?? randomBytes(32).toString('base64url');
const localDirectory = join(process.env.MOBILE_CODEX_DATA_DIR ?? process.cwd(), '.local');
await mkdir(localDirectory, { recursive: true });
const tokenFile = join(localDirectory, 'local-token');
if (!process.env.MOBILE_CODEX_LOCAL_TOKEN) await writeFile(tokenFile, token, { mode: 0o600 });
if (option('--tls-cert') || option('--tls-key')) {
  if (!option('--tls-cert') || !option('--tls-key')) throw new Error('--tls-cert and --tls-key are both required');
  devices = new DeviceStore(join(localDirectory, 'devices.json')); await devices.load();
  mobile = createMobileServer(bridge, devices, { cert: option('--tls-cert')!, key: option('--tls-key')! });
  const mobilePort = Number(option('--mobile-port') ?? 37842);
  const bind = option('--mobile-bind') ?? '0.0.0.0';
  mobile.server.on('error', async (error) => { console.error(error.message); await bridge.close(); process.exitCode = 1; });
  mobile.server.listen(mobilePort, bind);
  if (pairUrl) {
    const url = new URL(pairUrl); if (url.protocol !== 'wss:' || url.pathname !== '/ws') throw new Error('--public-url/--pair-url must be wss://host/ws');
    await writeFile(join(localDirectory, 'pairing.json'), JSON.stringify({ url: url.href, fingerprint: mobile.fingerprint, ...devices.beginPairing() }, null, 2), { mode: 0o600 });
  }
}
uiStatus = () => {
  const backends = bridge.listBackends();
  const backendDetails = bridge.uiStatus().backends;
  const frida = backendDetails.find((backend: any) => backend.kind === 'desktop-shared')?.details as any;
  return {
    ...bridge.uiStatus(),
    wss: mobile ? { status: 'listening', url: mobileUrl(), fingerprint: mobile.fingerprint } : { status: 'disabled' },
    devices: devices?.list() ?? [],
    parameters: {
      'listen address': { value: '127.0.0.1', restartRequired: true },
      'admin port': { value: port, restartRequired: true },
      'mobile listen address': { value: option('--mobile-bind') ?? '0.0.0.0', restartRequired: true },
      'mobile port': { value: Number(option('--mobile-port') ?? 37842), restartRequired: true },
      'public URL': { value: pairUrl ?? '自动生成', restartRequired: true },
      'workspace': { value: resolve(workspace), restartRequired: true },
      'TLS': { value: mobile ? 'enabled' : 'disabled', restartRequired: true },
      'backend': { value: backends.map((backend) => backend.id).join(', ') || 'none', restartRequired: true },
    },
    features: {
      'control-mode': {
        label: '控制模式（allow-control）',
        enabled: frida?.control?.allowControl === true,
        editable: frida?.control?.startupAllowControl === true,
        reason: frida?.control?.startupAllowControl === true ? '实时生效' : '启动 Bridge 时需要 --allow-control',
      },
      'approval-forwarding': {
        label: '审批转发',
        enabled: frida?.control?.allowApprovals === true,
        editable: frida?.control?.startupAllowControl === true,
        reason: frida?.control?.startupAllowControl === true ? '实时生效' : '启动 Bridge 时需要 --allow-control',
      },
      'event-stream': { label: '事件流', enabled: bridge.eventStreamEnabled, editable: true, reason: '实时生效' },
      'wss': { label: 'WSS 服务', enabled: Boolean(mobile), editable: false, reason: mobile ? '由启动参数控制' : '未启用 TLS/WSS' },
      'frida-hooks': { label: 'Frida hooks', enabled: frida?.injection?.hooksInstalled === true, editable: false, reason: frida?.injection?.hooksRestored ? '卸载时已恢复' : '由 Bridge 生命周期管理' },
    },
    frida: frida ?? { helper: { status: 'unavailable' }, injection: { hooksInstalled: false, hooksRestored: false } },
    environment: [
      { name: 'Codex Desktop 兼容性', status: frida ? 'PASS' : 'WARN', reason: frida ? '版本和运行时已通过 adapter 检查' : 'Desktop shared backend 未连接' },
      { name: '目标 PID', status: frida?.injection?.targetPid ? 'PASS' : 'WARN', reason: String(frida?.injection?.targetPid ?? '未附加') },
      { name: 'Node', status: 'PASS', reason: process.versions.node },
      { name: 'Python', status: frida?.helper?.pythonVersion ? 'PASS' : 'WARN', reason: frida?.helper?.pythonVersion ?? 'helper 版本不可用' },
      { name: 'Frida', status: frida?.helper?.fridaVersion ? 'PASS' : 'WARN', reason: frida?.helper?.fridaVersion ?? 'helper 版本不可用' },
      { name: 'Frida helper', status: frida?.helper?.status === 'running' ? 'PASS' : 'FAIL', reason: frida?.diagnostic ?? 'helper 状态不可用' },
      { name: 'TLS 证书', status: mobile ? 'PASS' : 'WARN', reason: mobile ? '证书已加载，fingerprint 显示在上方' : 'WSS 未启用' },
      { name: 'TLS 端口', status: mobile ? 'PASS' : 'WARN', reason: mobile ? String(Number(option('--mobile-port') ?? 37842)) : 'WSS 未启用' },
      { name: 'Hooks', status: frida?.injection?.hooksInstalled ? 'PASS' : 'WARN', reason: frida?.injection?.hooksRestored ? '上次卸载时已恢复' : '正在运行或尚未验证' },
    ],
  };
};
server = createHttpServer(bridge, token, devices, {
  token: uiSession,
  expiresAt: uiSessionExpiresAt,
  status: () => uiStatus?.() ?? bridge.uiStatus(),
  pairing: () => pairingPayload(),
});
const port = adminPort;
server.on('error', async (error) => { console.error(error.message); await bridge.close(); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => {
  // The session is delivered only to the injected renderer over the existing
  // in-process command channel; it is never printed or sent to mobile.
  console.log(JSON.stringify({ listening: `http://127.0.0.1:${(server!.address() as any).port}`, mobile: mobile ? { fingerprint: mobile.fingerprint, pairingFile: option('--pair-url') ? join(localDirectory, 'pairing.json') : undefined } : undefined, tokenFile: process.env.MOBILE_CODEX_LOCAL_TOKEN ? undefined : tokenFile, backends: bridge.listBackends(), renderer: bridge.uiStatus().backends.filter((backend: any) => backend.kind === 'desktop-shared').map((backend: any) => backend.details.renderer ?? {}) }));
});
const shutdown = async () => { server?.close(); mobile?.close(); await bridge.close(); process.exit(0); };
process.once('SIGINT', shutdown); process.once('SIGTERM', shutdown);
} catch (error) {
  server?.close(); mobile?.close();
  await bridge.close();
  console.error(error instanceof Error ? error.message : 'Bridge startup failed');
  process.exitCode = 1;
}
