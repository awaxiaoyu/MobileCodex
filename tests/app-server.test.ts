import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { AppServerBackend } from '../src/app-server.ts';
import { Bridge } from '../src/bridge.ts';

test('stdio adapter routes task, native approval id, delta and resolved exactly once in one connection', { timeout: 5000 }, async () => {
  const backend = new AppServerBackend({ command: process.execPath, args: [fileURLToPath(new URL('./fixtures/app-server.mjs', import.meta.url))], workspace: process.cwd() });
  const bridge = new Bridge();
  const events: any[] = [];
  bridge.on('event', (event) => events.push(event));
  try {
    await bridge.addBackend(backend);
    const context = { backendId: backend.id, backendGeneration: backend.generation };
    const request = (id: string, method: string, payload: any) => bridge.handle({ v: 1, kind: 'request', id, method, ...context, payload });
    const created = await request('create', 'bridge.thread.create', { projectId: 'workspace' });
    const waitApproval = once(bridge, 'event');
    const turn = await request('start', 'bridge.turn.start', { threadId: created.payload.thread.id, input: [{ type: 'text', text: 'fixture' }] });
    assert.equal(turn.kind, 'response');
    assert.equal(turn.payload.turn.items, undefined);
    await waitApproval;
    const approval = events.find((e) => e.kind === 'server.request');
    assert.ok(approval);
    const malformed = await bridge.handle({ v: 1, id: approval.id, kind: 'server.response', method: approval.method, ...context, payload: { decision: 'invalid' } });
    assert.equal(malformed.kind, 'error');
    assert.equal(malformed.payload.code, 'protocol.invalid_params');
    // Client envelopes omit server event sequence fields.
    const response = { v: 1, id: approval.id, kind: 'server.response', method: approval.method, ...context, payload: { decision: 'accept' } };
    const nextEvent = once(bridge, 'event');
    assert.equal((await bridge.handle(response)).payload.submitted, true);
    assert.equal((await bridge.handle(response)).payload.code, 'server_request.resolved');
    await nextEvent;
    await new Promise<void>((resolve) => {
      if (events.some((e) => e.method === 'event.task.status' && e.payload.status === 'completed')) return resolve();
      const listener = (e: any) => { if (e.method === 'event.task.status' && e.payload.status === 'completed') { bridge.off('event', listener); resolve(); } };
      bridge.on('event', listener);
    });
    assert.ok(events.some((e) => e.method === 'event.item.delta' && e.payload.delta === 'approved'));
    assert.equal(events.some((e) => JSON.stringify(e).includes('private output')), false);
    assert.ok(events.some((e) => e.method === 'event.serverRequest.resolved' && e.payload.requestId === approval.id));
  } finally { await bridge.close(); }
});
