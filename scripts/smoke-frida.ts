import { FridaBackend } from '../src/frida-backend.ts';
import { discoverDesktop } from '../src/discovery.ts';
import { resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const found = await discoverDesktop() as any;
const pid = found.desktop?.[0]?.ProcessId;
if (!pid) throw new Error('No running Codex Desktop Main found');
const backend = new FridaBackend({ workspace: resolve('.'), pid, deps: process.env.MOBILE_CODEX_FRIDA_DEPS });
const output: any = { timestamp: new Date().toISOString(), adapter: 'frida-shared', pid };
const diagnostics: string[] = [];
backend.on('diagnostic', (value) => diagnostics.push(value));
backend.on('transport.status', (value) => { if (process.env.MOBILE_CODEX_TRACE === '1') console.error(JSON.stringify(value)); });
try {
  await backend.start();
  output.connected = backend.status === 'connected';
  const models = await backend.call('model/list', { limit: 100 });
  const threads = await backend.call('bridge.thread.list', { limit: 20 });
  output.models = models.data?.length;
  output.threads = threads.threads?.length;
  const threadId = process.env.CODEX_THREAD_ID ?? threads.threads?.[0]?.id;
  if (threadId) {
    const read = await backend.call('bridge.thread.read', { threadId });
    output.read = { succeeded: !!read.thread?.id, turns: read.thread?.turns?.length };
  }
} catch (error) { output.error = error instanceof Error ? error.message : String(error); output.diagnostics = diagnostics; process.exitCode = 1; }
finally {
  await backend.close(); output.closed = backend.status === 'stopped'; output.cleanup = backend.lastCleanup;
  await mkdir('.local', { recursive: true });
  await writeFile('.local/frida-smoke.json', JSON.stringify(output, null, 2));
  console.log(JSON.stringify(output, null, 2));
}
