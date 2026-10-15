import test from 'node:test';
import assert from 'node:assert/strict';
import { installApprovalArbitration } from '../adapters/main/arbitration.js';

test('Desktop and mobile share one response claim, preserving original Promise and cleanup', async () => {
  let calls = 0;
  const promise = Promise.resolve();
  const original = function () { calls++; return promise; };
  const handlers = new Map([['channel', original]]);
  const request = { hostId: 'local', type: 'mcp-response', requestMethod: 'item/fileChange/requestApproval', response: { id: 12, result: { decision: 'accept' } } };
  const arbitration = installApprovalArbitration(handlers, 'channel', new Map(), () => {});
  assert.equal(handlers.get('channel')!({}, request), promise);
  assert.deepEqual(await handlers.get('channel')!({}, request), { mobileCodexAlreadyResponded: true, state: 'submitting' });
  assert.equal(calls, 1);
  assert.equal(arbitration.hasClaimed('local', 12), true);
  assert.equal(arbitration.restore(), true);
  assert.equal(handlers.get('channel'), original);
});

test('failed approval delivery stays unknown and is not automatically submitted again', async () => {
  const error = new Error('delivery failed');
  const handlers = new Map([['channel', () => { throw error; }]]);
  installApprovalArbitration(handlers, 'channel', new Map(), () => {});
  const request = { hostId: 'local', type: 'mcp-response', requestMethod: 'item/fileChange/requestApproval', response: { id: 's', result: { decision: 'accept' } } };
  assert.throws(() => handlers.get('channel')!({}, request), (value) => value === error);
  assert.equal((await handlers.get('channel')!({}, request)).state, 'unknown');
});
