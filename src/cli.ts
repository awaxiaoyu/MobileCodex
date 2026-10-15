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

const args = process.argv.slice(2);
const command = args[0] ?? 'serve';
const option = (name: string) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
if (command === 'discover') { console.log(JSON.stringify(await discoverDesktop(), null, 2)); process.exit(0); }
if (command !== 'serve') throw new Error('Usage: node src/cli.ts discover|serve [--port N] [--standalone] [--workspace PATH] [--frida] [--pid PID]');
if (args.includes('--frida') && option('--cdp')) throw new Error('Select one shared adapter: --frida or --cdp');

const workspace = option('--workspace') ?? process.env.MOBILE_CODEX_WORKSPACE ?? process.cwd();
const bridge = new Bridge({ workspace });
let toolsBackend: DesktopToolsBackend | undefined;
let mobile: ReturnType<typeof createMobileServer> | undefined;
let server: ReturnType<typeof createHttpServer> | undefined;
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
  await bridge.addBackend(new FridaBackend({ workspace: resolve(workspace), pid: desktopPid, python: process.env.MOBILE_CODEX_FRIDA_PYTHON, deps: process.env.MOBILE_CODEX_FRIDA_DEPS, allowControl: args.includes('--allow-control'), projectProvider: async () => toolsBackend ? await toolsBackend.call('bridge.project.list', {}) : { projects: [] } }));
}
if (process.env.CODEX_APP_TOOLS_PIPE_PATH && process.env.CODEX_THREAD_ID) {
  // This is a tools-only backend. It is never labelled desktop-shared and does
  // not pretend to control the Desktop live turn.
  toolsBackend = new DesktopToolsBackend({ pipePath: process.env.CODEX_APP_TOOLS_PIPE_PATH, threadId: process.env.CODEX_THREAD_ID, turnId: process.env.MOBILE_CODEX_TURN_ID ?? 'bridge-readonly-probe', hostId: process.env.CODEX_APP_TOOLS_CALLER_HOST_ID });
  await bridge.addBackend(toolsBackend);
}
const token = process.env.MOBILE_CODEX_LOCAL_TOKEN ?? randomBytes(32).toString('base64url');
const localDirectory = join(process.cwd(), '.local');
await mkdir(localDirectory, { recursive: true });
const tokenFile = join(localDirectory, 'local-token');
if (!process.env.MOBILE_CODEX_LOCAL_TOKEN) await writeFile(tokenFile, token, { mode: 0o600 });
let devices: DeviceStore | undefined;
if (option('--tls-cert') || option('--tls-key')) {
  if (!option('--tls-cert') || !option('--tls-key')) throw new Error('--tls-cert and --tls-key are both required');
  devices = new DeviceStore(join(localDirectory, 'devices.json')); await devices.load();
  mobile = createMobileServer(bridge, devices, { cert: option('--tls-cert')!, key: option('--tls-key')! });
  const mobilePort = Number(option('--mobile-port') ?? 37842);
  const bind = option('--mobile-bind') ?? '0.0.0.0';
  mobile.server.on('error', async (error) => { console.error(error.message); await bridge.close(); process.exitCode = 1; });
  mobile.server.listen(mobilePort, bind);
  if (option('--pair-url')) {
    const url = new URL(option('--pair-url')!); if (url.protocol !== 'wss:') throw new Error('--pair-url must use wss');
    await writeFile(join(localDirectory, 'pairing.json'), JSON.stringify({ url: url.href, fingerprint: mobile.fingerprint, ...devices.beginPairing() }, null, 2), { mode: 0o600 });
  }
}
server = createHttpServer(bridge, token, devices);
const port = Number(option('--port') ?? process.env.MOBILE_CODEX_PORT ?? 37841);
server.on('error', async (error) => { console.error(error.message); await bridge.close(); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log(JSON.stringify({ listening: `http://127.0.0.1:${(server!.address() as any).port}`, mobile: mobile ? { fingerprint: mobile.fingerprint, pairingFile: option('--pair-url') ? join(localDirectory, 'pairing.json') : undefined } : undefined, tokenFile: process.env.MOBILE_CODEX_LOCAL_TOKEN ? undefined : tokenFile, backends: bridge.listBackends() })));
const shutdown = async () => { server?.close(); mobile?.close(); await bridge.close(); process.exit(0); };
process.once('SIGINT', shutdown); process.once('SIGTERM', shutdown);
} catch (error) {
  server?.close(); mobile?.close();
  await bridge.close();
  console.error(error instanceof Error ? error.message : 'Bridge startup failed');
  process.exitCode = 1;
}
