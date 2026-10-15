import { FridaBackend } from '../src/frida-backend.ts';
import { discoverDesktop } from '../src/discovery.ts';
import { Bridge } from '../src/bridge.ts';
import { randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const previous = JSON.parse(await readFile('.local/turn-smoke.json', 'utf8'));
const found = await discoverDesktop() as any;
const backend = new FridaBackend({ workspace: resolve('.'), pid: found.desktop?.[0]?.ProcessId, allowControl: true });
const bridge = new Bridge(); const evidence: any = { timestamp: new Date().toISOString(), threadId: previous.threadId, plan: false, userInput: false };
const call = async (method: string, payload: any, kind = 'request', id = randomUUID()) => {
  const response = await bridge.handle({ v: 1, kind, id, method, payload, backendId: backend.id, backendGeneration: backend.generation });
  if (response.kind === 'error') throw new Error(JSON.stringify(response.payload)); return response.payload;
};
let turnId: string | undefined;
let answerPromise: Promise<any> | undefined;
bridge.on('event', (event) => {
  if (event.threadId !== previous.threadId || event.kind !== 'server.request' || event.method !== 'item/tool/requestUserInput' || answerPromise) return;
  evidence.userInput = true; evidence.requestId = event.id;
  const answers = Object.fromEntries((event.payload.questions ?? []).map((q: any) => [q.id, { answers: [q.options?.[0]?.label ?? '使用方案 A'] }]));
  answerPromise = call(event.method, { answers }, 'server.response', event.id).then(async () => {
    evidence.reply = true;
    const duplicate = await bridge.handle({ v: 1, kind: 'server.response', id: event.id, method: event.method, payload: { answers }, backendId: backend.id, backendGeneration: backend.generation });
    evidence.duplicateRejected = duplicate.kind === 'error';
  }).catch((error) => { evidence.replyError = error.message; });
});
try {
  await bridge.addBackend(backend);
  await call('bridge.thread.resume', { threadId: previous.threadId });
  const model = previous.selection.model; const effort = previous.selection.effort;
  const result = await call('bridge.turn.start', { threadId: previous.threadId, input: [{ type: 'text', text: '这是 Plan 模式与用户问题的集成测试。请现在调用 request_user_input 工具，询问测试用户选择方案 A 还是 B，提供两个选项。收到回复后用一句话确认选择并结束。不要操作文件、命令或网络。' }], model, effort, collaborationMode: { mode: 'plan', settings: { model, reasoning_effort: effort, developer_instructions: null } } });
  turnId = result.turn.id; evidence.plan = true;
  const deadline = Date.now() + 60000;
  while (!answerPromise && Date.now() < deadline) await new Promise((r) => setTimeout(r, 250));
  if (answerPromise) await answerPromise;
  for (let i = 0; i < 40; i++) { await new Promise((r) => setTimeout(r, 200)); const pending = [...bridge.serverRequests.values()].find((p) => p.params.threadId === previous.threadId); if (pending?.state === 'resolved') { evidence.resolved = true; break; } }
  for (let attempt = 0; attempt < 8; attempt++) {
    try { const snapshot = await call('bridge.snapshot.get', { threadId: previous.threadId }); evidence.snapshot = { succeeded: !!snapshot.thread?.id, approvals: snapshot.approvals?.length }; break; }
    catch (error) { if (!String(error).includes('snapshot.unstable') || attempt === 7) throw error; await new Promise((r) => setTimeout(r, 500)); }
  }
} catch (error) { evidence.error = error instanceof Error ? error.message : String(error); process.exitCode = 1; }
finally {
  if (turnId) try { await call('bridge.turn.interrupt', { threadId: previous.threadId, turnId }); } catch {}
  await bridge.close(); evidence.cleanup = backend.lastCleanup;
  await writeFile('.local/plan-smoke.json', JSON.stringify(evidence, null, 2)); console.log(JSON.stringify(evidence, null, 2));
}
