import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Bridge } from '../src/bridge.ts';
import { validateNativeRequest } from '../src/policy.ts';

class FakeBackend extends EventEmitter {
  id = 'fake';
  kind = 'companion-standalone' as const;
  generation = 1;
  status = 'stopped';
  methods = new Set(['bridge.thread.list', 'codex.request']);
  responses: any[] = [];
  async start() { this.status = 'connected'; }
  async close() { this.status = 'stopped'; }
  async call(method: string, params: any) {
    if (method === 'thread/list') return { data: [{ id: 'thread-1', title: 'Test' }] };
    return { method, params };
  }
  respond(id: number | string, result: any) { this.responses.push({ id, result }); }
}

test('policy accepts only the P0 native request allowlist', () => {
  assert.doesNotThrow(() => validateNativeRequest('turn/interrupt', { threadId: 't', turnId: 'u' }));
  assert.throws(() => validateNativeRequest('thread/shellCommand', { command: 'dir' }), (error: any) => error.code === 'policy.method_not_allowed');
  assert.throws(() => validateNativeRequest('turn/start', { threadId: 't', input: [{ type: 'text', text: 'x' }], cwd: 'C:\\secret' }), (error: any) => error.code === 'policy.field_not_allowed');
  assert.throws(() => validateNativeRequest('turn/start', { threadId: 't', input: [{ type: 'image', url: 'x' }] }), (error: any) => error.code === 'policy.input_not_supported');
});

test('bridge routes a native request and rejects excluded APIs', async () => {
  const bridge = new Bridge();
  await bridge.addBackend(new FakeBackend() as any);
  const response = await bridge.handle({ v: 1, id: 'r1', kind: 'request', method: 'codex.request', backendId: 'fake', backendGeneration: 1, payload: { method: 'turn/interrupt', params: { threadId: 't', turnId: 'u' } } });
  assert.equal(response.kind, 'response');
  assert.equal(response.payload.method, 'turn/interrupt');
  const denied = await bridge.handle({ v: 1, id: 'r2', kind: 'request', method: 'codex.request', backendId: 'fake', backendGeneration: 1, payload: { method: 'thread/shellCommand', params: { command: 'dir' } } });
  assert.equal(denied.kind, 'error');
  assert.equal(denied.payload.code, 'policy.method_not_allowed');
  const stale = await bridge.handle({ v: 1, id: 'r3', kind: 'request', method: 'bridge.thread.list', backendId: 'fake', backendGeneration: 2, payload: {} });
  assert.equal(stale.payload.code, 'backend.generation_mismatch');
});

test('bridge emits bounded, resumable events', async () => {
  const bridge = new Bridge({ maxEventCache: 2 });
  const backend = new FakeBackend();
  await bridge.addBackend(backend as any);
  const events: any[] = [];
  bridge.on('event', (event) => events.push(event));
  backend.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: 't', turnId: 'u', itemId: 'i', delta: 'a' } });
  backend.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: 't', turnId: 'u', itemId: 'i', delta: 'b' } });
  backend.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: 't', turnId: 'u', itemId: 'i', delta: 'c' } });
  assert.deepEqual(events.map((e) => e.seq), [1, 2, 3]);
  assert.deepEqual(bridge.resume('fake', 1).events.map((e) => e.payload.delta), ['b', 'c']);
  assert.throws(() => bridge.resume('fake', 0), (error: any) => error.code === 'snapshot.required');
});

test('bridge returns a structured error instead of throwing for request failures', async () => {
  const bridge = new Bridge();
  await bridge.addBackend(new FakeBackend() as any);
  const result = await bridge.handle({ v: 1, id: 'r1', kind: 'request', method: 'bridge.nope', backendId: 'fake', backendGeneration: 1, payload: {} });
  assert.equal(result.kind, 'error');
  assert.equal(result.payload.code, 'capability.unavailable');
});

test('same id coalesces pending mutations and conflicting params are rejected', async () => {
  const backend = new FakeBackend(); let calls = 0;
  backend.call = async () => { calls++; await new Promise((resolve) => setTimeout(resolve, 10)); return { ok: true }; };
  const bridge = new Bridge(); await bridge.addBackend(backend as any);
  const input = { v: 1, id: 'same', kind: 'request', method: 'codex.request', backendId: 'fake', backendGeneration: 1, payload: { method: 'turn/interrupt', params: { threadId: 't', turnId: 'u' } } };
  const [first, second] = await Promise.all([bridge.handle(input), bridge.handle(input)]);
  assert.deepEqual(first, second); assert.equal(calls, 1);
  const conflict = await bridge.handle({ ...input, payload: { method: 'turn/interrupt', params: { threadId: 't', turnId: 'changed' } } });
  assert.equal(conflict.payload.code, 'request.id_conflict');
});

test('business aliases cannot bypass native field policy', async () => {
  const backend = new FakeBackend(); backend.methods.add('bridge.turn.start');
  const bridge = new Bridge(); await bridge.addBackend(backend as any);
  const denied = await bridge.handle({ v: 1, id: 'alias', kind: 'request', method: 'bridge.turn.start', backendId: 'fake', backendGeneration: 1, payload: { threadId: 't', input: [{ type: 'text', text: 'run tests' }], approvalPolicy: 'never' } });
  assert.equal(denied.payload.code, 'policy.field_not_allowed');
});

test('snapshot includes stable cursor and rejects a changing task', async () => {
  const backend = new FakeBackend(); backend.methods.add('bridge.thread.read');
  const bridge = new Bridge(); await bridge.addBackend(backend as any);
  backend.call = async () => ({ thread: { id: 't', turns: [] } });
  const input = { v: 1, id: 'snap', kind: 'request', method: 'bridge.snapshot.get', backendId: 'fake', backendGeneration: 1, payload: { threadId: 't' } };
  const stable = await bridge.handle(input); assert.equal(stable.kind, 'snapshot'); assert.equal(stable.seq, 0);
  backend.call = async () => { backend.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: 't', turnId: 'u', itemId: 'i', delta: 'x' } }); return { thread: { id: 't' } }; };
  assert.equal((await bridge.handle({ ...input, id: 'changing' })).payload.code, 'snapshot.unstable');
  assert.throws(() => validateNativeRequest('turn/start', { threadId: 't', input: [{ type: 'text', text: 'x' }], collaborationMode: { mode: 'plan', settings: { model: 'm', developer_instructions: 'override' } } }), (e: any) => e.code === 'policy.field_not_allowed');
});
