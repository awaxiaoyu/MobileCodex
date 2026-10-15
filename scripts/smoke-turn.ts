import { FridaBackend } from '../src/frida-backend.ts';
import { discoverDesktop } from '../src/discovery.ts';
import { Bridge } from '../src/bridge.ts';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const desktop = await discoverDesktop() as any;
const backend = new FridaBackend({ workspace: resolve('.'), pid: desktop.desktop?.[0]?.ProcessId, allowControl: true });
const bridge = new Bridge();
const evidence: any = { timestamp: new Date().toISOString(), adapter: 'desktop-shared', testChat: true };
let threadId: string | undefined;
let turnId: string | undefined;
const events: any[] = [];
bridge.on('event', (event) => { if (event.threadId === threadId) events.push(event); });
const call = async (method: string, payload: any) => {
  const response = await bridge.handle({ v: 1, kind: 'request', id: randomUUID(), backendId: backend.id, backendGeneration: backend.generation, method, payload });
  if (response.kind === 'error') throw new Error(JSON.stringify(response.payload));
  return response.payload;
};
try {
  await bridge.addBackend(backend);
  const created = await call('bridge.thread.create', { projectId: 'workspace' });
  threadId = created.thread.id; evidence.threadId = threadId;
  const models = await call('bridge.model.list', { limit: 100 });
  const selected = models.data.find((m: any) => m.isDefault) ?? models.data[0];
  const model = selected.model ?? selected.id;
  const effort = selected.supportedReasoningEfforts?.find((e: any) => e.reasoningEffort === 'low')?.reasoningEffort ?? selected.defaultReasoningEffort;
  evidence.selection = { model, effort };
  const started = await call('bridge.turn.start', { threadId, input: [{ type: 'text', text: '这是 MobileCodex Bridge 集成测试聊天。不要调用工具、不要修改文件。请详细解释 1 到 200 的整数各自有什么数学特点，按顺序输出。' }], model, effort });
  turnId = started.turn.id; evidence.start = { succeeded: true, turnId };
  const deadline = Date.now() + 60000;
  while (!events.some((e) => e.method === 'event.item.delta') && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
  evidence.streaming = events.some((e) => e.method === 'event.item.delta');
  if (evidence.streaming && !events.some((e) => e.method === 'event.task.status' && e.payload.status === 'completed')) {
    const steered = await call('bridge.turn.steer', { threadId, expectedTurnId: turnId, input: [{ type: 'text', text: '追加：请继续详细展开，不使用工具。' }] });
    evidence.steer = { succeeded: true, keys: Object.keys(steered) };
    await call('bridge.turn.interrupt', { threadId, turnId });
    evidence.interrupt = { succeeded: true };
    for (let i = 0; i < 40 && !events.some((e) => e.payload.status === 'interrupted'); i++) await new Promise((r) => setTimeout(r, 200));
    evidence.interrupt.notification = events.some((e) => e.payload.status === 'interrupted');
  }
  const read = await call('bridge.thread.read', { threadId });
  evidence.read = { turns: read.thread.turns?.length, lastStatus: read.thread.turns?.at(-1)?.status };
  evidence.events = events.reduce((counts: any, event) => { counts[event.method] = (counts[event.method] ?? 0) + 1; return counts; }, {});
} catch (error) { evidence.error = error instanceof Error ? error.message : String(error); process.exitCode = 1; }
finally {
  if (threadId && turnId && !evidence.interrupt?.succeeded) try { await call('bridge.turn.interrupt', { threadId, turnId }); evidence.cleanupInterrupt = true; } catch {}
  await bridge.close(); evidence.cleanup = backend.lastCleanup;
  await mkdir('.local', { recursive: true }); await writeFile('.local/turn-smoke.json', JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
}
