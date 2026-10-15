import { WebSocket } from 'ws';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { resolve, join } from 'node:path';
import { mkdir, readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { Bridge } from '../src/bridge.ts';
import { FridaBackend } from '../src/frida-backend.ts';
import { DesktopToolsBackend } from '../src/desktop-tools.ts';
import { discoverDesktop } from '../src/discovery.ts';
import { DeviceStore } from '../src/devices.ts';
import { createMobileServer } from '../src/mobile-server.ts';

const desktop = await discoverDesktop() as any;
const bridge = new Bridge({ workspace: resolve('.') });
const tools = process.env.CODEX_APP_TOOLS_PIPE_PATH && process.env.CODEX_THREAD_ID ? new DesktopToolsBackend({ pipePath: process.env.CODEX_APP_TOOLS_PIPE_PATH, threadId: process.env.CODEX_THREAD_ID, turnId: 'bridge-readonly-mobile-smoke' }) : undefined;
const backend = new FridaBackend({ workspace: resolve('.'), pid: desktop.desktop?.[0]?.ProcessId, projectProvider: async () => tools ? await tools.call('bridge.project.list', {}) : { projects: [] } });
const root = await mkdtemp(join(tmpdir(), 'mobile-live-'));
const evidence: any = { timestamp: new Date().toISOString(), transport: 'WSS', backend: 'actual-desktop-shared' };
let mobile: ReturnType<typeof createMobileServer> | undefined;
let socket: WebSocket | undefined;
try {
  if (tools) await bridge.addBackend(tools);
  await bridge.addBackend(backend);
  const key = join(root, 'key.pem'), cert = join(root, 'cert.pem');
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1'], { windowsHide: true, stdio: 'ignore' });
  const devices = new DeviceStore(join(root, 'devices.json')); await devices.load();
  const pairing = devices.beginPairing(); const device = await devices.pair(pairing.id, pairing.secret, 'mobile-integration-test');
  mobile = createMobileServer(bridge, devices, { cert, key }); mobile.server.listen(0, '127.0.0.1'); await once(mobile.server, 'listening');
  const port = (mobile.server.address() as any).port;
  socket = new WebSocket(`wss://127.0.0.1:${port}/ws`, { ca: await readFile(cert), headers: { authorization: `Bearer ${device.token}` } });
  const ready = once(socket, 'message'); await once(socket, 'open'); await ready;
  const call = (method: string, payload: any) => new Promise<any>((resolve, reject) => {
    const id = randomUUID(); const listener = (bytes: any) => { const result = JSON.parse(bytes.toString()); if (result.id !== id) return; clearTimeout(timer); socket!.off('message', listener); result.kind === 'error' ? reject(new Error(JSON.stringify(result.payload))) : resolve(result); };
    const timer = setTimeout(() => { socket!.off('message', listener); reject(new Error('Mobile test request timed out')); }, 30000);
    socket!.on('message', listener); socket!.send(JSON.stringify({ v: 1, kind: 'request', id, method, payload, backendId: backend.id, backendGeneration: backend.generation }));
  });
  const projects = await call('bridge.project.list', {}); evidence.projectCount = projects.payload.projects.length;
  const models = await call('bridge.model.list', { limit: 100 }); evidence.modelCount = models.payload.data.length;
  const threads = await call('bridge.thread.list', { limit: 20 }); evidence.threadCount = threads.payload.threads.length;
  const test = JSON.parse(await readFile('.local/turn-smoke.json', 'utf8'));
  const snapshot = await call('bridge.snapshot.get', { threadId: test.threadId }); evidence.snapshot = { succeeded: snapshot.kind === 'snapshot', hasCursor: !!snapshot.streamId, seq: snapshot.seq };
  const resumed = await call('bridge.events.resume', { streamId: snapshot.streamId, afterSeq: snapshot.seq }); evidence.resume = resumed.payload.status;
  const closed = once(socket, 'close'); await devices.revoke(device.deviceId); evidence.revokeCloseCode = (await closed)[0];
} catch (error) { evidence.error = error instanceof Error ? error.message : String(error); process.exitCode = 1; }
finally {
  socket?.terminate(); mobile?.close(); await bridge.close(); evidence.cleanup = backend.lastCleanup;
  await rm(root, { recursive: true, force: true });
  await mkdir('.local', { recursive: true }); await writeFile('.local/mobile-desktop-smoke.json', JSON.stringify(evidence, null, 2)); console.log(JSON.stringify(evidence, null, 2));
}
