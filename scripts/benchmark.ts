import { EventEmitter, once } from 'node:events';
import { createServer as createNetServer, type Server as NetServer } from 'node:net';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { cpuUsage } from 'node:process';
import { performance } from 'node:perf_hooks';
import { WebSocket } from 'ws';
import { Bridge } from '../src/bridge.ts';
import { DeviceStore } from '../src/devices.ts';
import { createMobileServer } from '../src/mobile-server.ts';
import { FrameDecoder, NativePipeClient, encodeFrame } from '../src/native-pipe.ts';
import type { Backend, JsonObject } from '../src/types.ts';

type Measurement = {
  name: string;
  status: 'completed' | 'unavailable' | 'failed';
  source: 'implementation' | 'fixture' | 'real-desktop';
  samples?: number;
  elapsedMs?: number;
  p50Ms?: number;
  p95Ms?: number;
  p99Ms?: number;
  throughputOpsPerSec?: number;
  cpuUserMs?: number;
  cpuSystemMs?: number;
  cpuPercent?: number;
  reason?: string;
  details?: Record<string, unknown>;
};

const iterations = positiveInt(process.env.MOBILE_CODEX_BENCH_ITERATIONS, 50_000);
const frameIterations = positiveInt(process.env.MOBILE_CODEX_BENCH_FRAMES, Math.max(iterations * 2, 100_000));
const wssIterations = positiveInt(process.env.MOBILE_CODEX_BENCH_WSS, 1_000);
const fridaIterations = positiveInt(process.env.MOBILE_CODEX_BENCH_FRIDA_ITERATIONS, 5);

function positiveInt(value: string | undefined, fallback: number) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function percentile(values: number[], fraction: number) {
  if (!values.length) return 0;
  const index = (values.length - 1) * fraction;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return values[lower];
  return values[lower] + (values[upper] - values[lower]) * (index - lower);
}

async function measure(name: string, count: number, operation: (index: number) => Promise<void> | void, source: Measurement['source'] = 'implementation', details?: Record<string, unknown>): Promise<Measurement> {
  const warmup = Math.min(20, count);
  for (let index = 0; index < warmup; index++) await operation(index);
  const samples: number[] = [];
  const beforeCpu = cpuUsage();
  const beforeUserUs = beforeCpu.user;
  const beforeSystemUs = beforeCpu.system;
  const started = performance.now();
  try {
    for (let index = 0; index < count; index++) {
      const sampleStarted = performance.now();
      await operation(index + warmup);
      samples.push(performance.now() - sampleStarted);
    }
  } catch (error) {
    return {
      name, status: 'failed', source,
      reason: error instanceof Error ? error.message : String(error),
      details,
    };
  }
  const elapsedMs = performance.now() - started;
  const afterCpu = cpuUsage();
  const cpu = { userMs: (afterCpu.user - beforeUserUs) / 1_000, systemMs: (afterCpu.system - beforeSystemUs) / 1_000 };
  samples.sort((left, right) => left - right);
  return {
    name, status: 'completed', source, samples: count, elapsedMs,
    p50Ms: percentile(samples, 0.50), p95Ms: percentile(samples, 0.95), p99Ms: percentile(samples, 0.99),
    throughputOpsPerSec: count / (elapsedMs / 1_000),
    cpuUserMs: cpu.userMs, cpuSystemMs: cpu.systemMs,
    cpuPercent: ((cpu.userMs + cpu.systemMs) / elapsedMs) * 100,
    details,
  };
}

class BenchmarkBackend extends EventEmitter implements Backend {
  id = 'benchmark';
  kind = 'companion-standalone' as const;
  generation = 1;
  status = 'stopped';
  methods = new Set(['bridge.thread.list']);
  async start() { this.status = 'connected'; }
  async close() { this.status = 'stopped'; }
  async call(method: string, params: JsonObject) { return { method, params, threads: [] }; }
}

async function benchmarkBridge() {
  const bridge = new Bridge();
  await bridge.addBackend(new BenchmarkBackend());
  const result = await measure('bridge.handle.fake-backend', iterations, async (index) => {
    const response = await bridge.handle({
      v: 1, kind: 'request', id: `bench-${index}`,
      method: 'bridge.thread.list', backendId: 'benchmark', backendGeneration: 1,
      payload: { limit: 20 },
    });
    if (response.kind !== 'response') throw new Error(`Unexpected bridge response: ${response.kind}`);
  }, 'implementation', { backend: 'in-process fake backend', path: 'Bridge.handle -> validation -> backend.call' });
  await bridge.close();
  return result;
}

async function benchmarkNativePipeCodec() {
  const payload = { jsonrpc: '2.0', id: 1, method: 'benchmark.echo', params: { text: 'x'.repeat(128) } };
  const decoder = new FrameDecoder();
  return measure('nativepipe.encode-decode', frameIterations, () => {
    const frames = decoder.push(encodeFrame(payload));
    if (frames.length !== 1) throw new Error('NativePipe fixture did not decode one frame');
  }, 'implementation', { fixture: 'in-process framing and decoding; no Codex Desktop pipe' });
}

async function createNativePipeFixture() {
  const pipePath = `\\\\.\\pipe\\mobile-codex-benchmark-${process.pid}-${Date.now()}`;
  const server = createNetServer((socket) => {
    const decoder = new FrameDecoder();
    socket.on('data', (chunk) => {
      try {
        for (const message of decoder.push(Buffer.from(chunk))) {
          socket.write(encodeFrame({ jsonrpc: '2.0', id: message.id, result: { ok: true } }));
        }
      } catch { socket.destroy(); }
    });
  });
  server.listen(pipePath);
  await once(server, 'listening');
  return { server, pipePath };
}

async function closeNetServer(server: NetServer) {
  if (!server.listening) return;
  await new Promise<void>((resolveClose) => server.close(() => resolveClose()));
}

async function benchmarkNativePipeRoundTrip() {
  let fixture: Awaited<ReturnType<typeof createNativePipeFixture>> | undefined;
  const client = { value: undefined as NativePipeClient | undefined };
  try {
    fixture = await createNativePipeFixture();
    client.value = new NativePipeClient(fixture.pipePath, 5_000);
    const result = await measure('nativepipe.named-pipe-roundtrip', iterations, async (index) => {
      const response = await client.value!.request('benchmark.echo', { index });
      if (!response?.ok) throw new Error('NativePipe fixture response was invalid');
    }, 'implementation', { fixture: 'local Windows named pipe echo; not the Codex Desktop NativePipe' });
    return result;
  } catch (error) {
    return {
      name: 'nativepipe.named-pipe-roundtrip', status: 'unavailable', source: 'implementation',
      reason: error instanceof Error ? error.message : String(error),
      details: { fixture: 'local Windows named pipe echo; not the Codex Desktop NativePipe' },
    } satisfies Measurement;
  } finally {
    client.value?.close();
    if (fixture) await closeNetServer(fixture.server);
  }
}

class SocketMessageRouter {
  private waiters: Array<{ predicate: (message: any) => boolean; resolve: (message: any) => void; reject: (error: unknown) => void }> = [];
  constructor(socket: WebSocket) {
    socket.on('message', (bytes) => this.receive(bytes));
    socket.on('error', (error) => this.fail(error));
  }
  wait(predicate: (message: any) => boolean) {
    return new Promise<any>((resolveMessage, reject) => this.waiters.push({ predicate, resolve: resolveMessage, reject }));
  }
  private receive(bytes: any) {
    let message: any;
    try { message = JSON.parse(bytes.toString()); }
    catch (error) { this.fail(error); return; }
    const pending = this.waiters.findIndex((waiter) => {
      try { return waiter.predicate(message); } catch { return false; }
    });
    if (pending >= 0) this.waiters.splice(pending, 1)[0].resolve(message);
  }
  private fail(error: unknown) {
    const waiters = this.waiters.splice(0);
    for (const waiter of waiters) waiter.reject(error);
  }
}

async function benchmarkWss() {
  const cert = process.env.MOBILE_CODEX_BENCH_TLS_CERT ?? resolve('.local/tls/cert.pem');
  const key = process.env.MOBILE_CODEX_BENCH_TLS_KEY ?? resolve('.local/tls/key.pem');
  if (!existsSync(cert) || !existsSync(key)) {
    return [{
      name: 'wss.rpc-roundtrip', status: 'unavailable', source: 'implementation',
      reason: 'TLS fixture not found; pass MOBILE_CODEX_BENCH_TLS_CERT and MOBILE_CODEX_BENCH_TLS_KEY',
    } satisfies Measurement];
  }
  const root = await mkdtemp(join(tmpdir(), 'mobile-codex-benchmark-'));
  const devices = new DeviceStore(join(root, 'devices.json'));
  await devices.load();
  const bridge = new Bridge();
  const backend = new BenchmarkBackend();
  await bridge.addBackend(backend);
  const mobile = createMobileServer(bridge, devices, { cert, key });
  const socket = mobile.server;
  let ws: WebSocket | undefined;
  let router: SocketMessageRouter | undefined;
  try {
    socket.listen(0, '127.0.0.1');
    await once(socket, 'listening');
    const port = (socket.address() as any).port;
    const pairing = devices.beginPairing();
    const paired = await devices.pair(pairing.id, pairing.secret, 'benchmark');
    ws = new WebSocket(`wss://127.0.0.1:${port}/ws`, { rejectUnauthorized: false, headers: { authorization: `Bearer ${paired.token}` } });
    router = new SocketMessageRouter(ws);
    await once(ws, 'open');
    await router.wait((message) => message.method === 'event.connection.ready');
    const rpc = await measure('wss.rpc-roundtrip', wssIterations, async (index) => {
      const id = `wss-bench-${index}`;
      ws!.send(JSON.stringify({ v: 1, kind: 'request', id, method: 'bridge.backends.list', payload: {} }));
      const response = await router!.wait((message) => message.id === id);
      if (response.kind !== 'response') throw new Error(`Unexpected WSS response: ${response.kind}`);
    }, 'implementation', { transport: 'TLS 1.2 loopback WebSocket', fixture: 'local server and fake backend' });

    const eventResult = await measure('wss.event-throughput', wssIterations, async (index) => {
      const itemId = `item-${index}`;
      const eventPromise = router!.wait((message) => message.method === 'event.item.delta' && message.payload?.itemId === itemId);
      backend.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: 'bench-thread', turnId: 'bench-turn', itemId, delta: 'x' } });
      await eventPromise;
    }, 'implementation', { transport: 'TLS 1.2 loopback WebSocket', fixture: 'local server event broadcast', eventCount: wssIterations });
    return [rpc, eventResult];
  } catch (error) {
    return [{
      name: 'wss.rpc-roundtrip', status: 'failed', source: 'implementation',
      reason: error instanceof Error ? error.message : String(error),
      details: { transport: 'TLS 1.2 loopback WebSocket' },
    } satisfies Measurement];
  } finally {
    ws?.terminate();
    const closed = socket.listening ? once(socket, 'close').then(() => undefined) : Promise.resolve();
    mobile.close();
    await closed;
    await bridge.close();
    await rm(root, { recursive: true, force: true });
  }
}

async function benchmarkFridaFixture() {
  const productionMinIntervalMs = 120;
  let nextAllowedAt = performance.now();
  const result = await measure('frida.dispatch-rate-fixture', fridaIterations, async () => {
    const remaining = nextAllowedAt - performance.now();
    if (remaining > 0) await new Promise<void>((resolveDelay) => setTimeout(resolveDelay, remaining));
    nextAllowedAt = performance.now() + productionMinIntervalMs;
  }, 'fixture', {
    fixture: 'Node timer queue applying the 120 ms production gate; no Desktop process or Frida attach',
    productionMinIntervalMs,
  });
  return result;
}

async function benchmarkRealFrida() {
  if (process.env.MOBILE_CODEX_BENCH_FRIDA !== '1') {
    return {
      name: 'frida.real-desktop-call', status: 'unavailable', source: 'real-desktop',
      reason: 'Set MOBILE_CODEX_BENCH_FRIDA=1 to attach a running Codex Desktop; no real attach was attempted',
      details: { productionMinIntervalMs: 120 },
    } satisfies Measurement;
  }
  try {
    const { discoverDesktop } = await import('../src/discovery.ts');
    const { FridaBackend } = await import('../src/frida-backend.ts');
    const discovered = await discoverDesktop() as any;
    const pid = Number(process.env.MOBILE_CODEX_BENCH_FRIDA_PID ?? discovered.desktop?.[0]?.ProcessId);
    if (!Number.isInteger(pid) || pid < 1) throw new Error('No running Codex Desktop Main process was discovered');
    const backend = new FridaBackend({ workspace: resolve('.'), pid, python: process.env.MOBILE_CODEX_FRIDA_PYTHON, deps: process.env.MOBILE_CODEX_FRIDA_DEPS });
    try {
      await backend.start();
      return await measure('frida.real-desktop-call', fridaIterations, async () => { await backend.call('model/list', { limit: 20 }); }, 'real-desktop', { pid, method: 'model/list', productionMinIntervalMs: 120 });
    } finally { await backend.close(); }
  } catch (error) {
    return {
      name: 'frida.real-desktop-call', status: 'unavailable', source: 'real-desktop',
      reason: error instanceof Error ? error.message : String(error),
      details: { productionMinIntervalMs: 120 },
    } satisfies Measurement;
  }
}

async function main() {
  const started = new Date().toISOString();
  const measurements: Measurement[] = [];
  measurements.push(await benchmarkBridge());
  measurements.push(await benchmarkNativePipeCodec());
  measurements.push(await benchmarkNativePipeRoundTrip());
  measurements.push(...await benchmarkWss());
  measurements.push(await benchmarkFridaFixture());
  measurements.push(await benchmarkRealFrida());
  const report = {
    schema: 'mobile-codex.benchmark/v1',
    startedAt: started,
    completedAt: new Date().toISOString(),
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    iterations: { bridge: iterations, nativePipeFrames: frameIterations, wss: wssIterations, frida: fridaIterations },
    measurements,
    notes: [
      'CPU time is measured for the Node process around each measured loop and includes local transport endpoints when applicable.',
      'NativePipe and WSS loopback results are fixtures for transport overhead, not measurements of a Codex Desktop process.',
      'Frida owner-thread fixture measures scheduler overhead only; real Desktop timing is unavailable unless MOBILE_CODEX_BENCH_FRIDA=1 is set.',
      'No C++ bridge_core implementation is selected or assumed by this benchmark.',
    ],
  };
  await mkdir('.local/benchmarks', { recursive: true });
  const file = join('.local/benchmarks', `benchmark-${started.replaceAll(/[:.]/g, '-')}.json`);
  await import('node:fs/promises').then(({ writeFile }) => writeFile(file, JSON.stringify(report, null, 2)));
  console.log(JSON.stringify({ ...report, reportFile: file }, null, 2));
}

await main();
