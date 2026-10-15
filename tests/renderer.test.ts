import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { installRendererProbe } from '../adapters/renderer/probe.js';
import { hookMethod } from '../adapters/renderer/hook.js';

test('renderer probe invokes original IPC, waits for actual response and unloads', async () => {
  const win = new EventTarget() as any;
  win.crypto = { randomUUID };
  win.electronBridge = {
    getDesktopUserAgent: () => 'Codex Desktop/26.1007.21434 (Windows NT 10.0; x64)',
    async sendMessageFromView(message: any) {
      assert.equal(message.type, 'mcp-request');
      const event = new Event('message') as any;
      event.data = { type: 'mcp-response', hostId: 'local', message: { id: message.request.id, result: { data: [1] } } };
      win.dispatchEvent(event);
    },
  };
  installRendererProbe(win);
  assert.deepEqual(await win.__mobileCodexProbe.call('model/list', {}), { data: [1] });
  await assert.rejects(win.__mobileCodexProbe.call('turn/start', { threadId: 't', input: [{ type: 'text', text: 'x' }] }), /Control is disabled/);
  await assert.rejects(win.__mobileCodexProbe.call('config/read', {}), /not registered/);
  win.__mobileCodexProbe.dispose();
  assert.equal(win.__mobileCodexProbe, undefined);
});

test('renderer refuses unsupported versions and does not install', () => {
  const win = { electronBridge: { sendMessageFromView() {}, getDesktopUserAgent: () => 'Codex Desktop/unknown' } };
  assert.throws(() => installRendererProbe(win), /Unsupported Desktop version/);
});

test('renderer reassembles Desktop chunked messages and acknowledges every sequence', async () => {
  const win = new EventTarget() as any;
  win.crypto = { randomUUID };
  const acknowledgements: any[] = [];
  win.electronBridge = {
    getDesktopUserAgent: () => 'Codex Desktop/26.1007.21434 (Windows NT; x64)',
    acknowledgeChunkedMessage: (...args: any[]) => acknowledgements.push(args),
    async sendMessageFromView(message: any) {
      const dispatch = (data: any) => { const event = new Event('message') as any; event.data = data; win.dispatchEvent(event); };
      dispatch({ marker: 'codex-host-chunked-message-v1', transferId: 't1', sequence: 1, kind: 'start' });
      dispatch({ marker: 'codex-host-chunked-message-v1', transferId: 't1', sequence: 2, kind: 'chunk', tokens: [
        { type: 'object-start' }, { type: 'key', value: 'type' }, { type: 'value', value: 'mcp-response' },
        { type: 'key', value: 'hostId' }, { type: 'value', value: 'local' },
        { type: 'key', value: 'message' }, { type: 'object-start' }, { type: 'key', value: 'id' }, { type: 'value', value: message.request.id },
        { type: 'key', value: 'result' }, { type: 'object-start' }, { type: 'key', value: 'data' }, { type: 'array-start' },
        { type: 'value', value: 'large' }, { type: 'container-end' }, { type: 'container-end' }, { type: 'container-end' }, { type: 'container-end' },
      ] });
      dispatch({ marker: 'codex-host-chunked-message-v1', transferId: 't1', sequence: 3, kind: 'end' });
    },
  };
  installRendererProbe(win);
  assert.deepEqual(await win.__mobileCodexProbe.call('model/list', {}), { data: ['large'] });
  assert.deepEqual(acknowledgements, [['t1', 1], ['t1', 2], ['t1', 3]]);
  win.__mobileCodexProbe.dispose();
});

test('hook preserves receiver, Promise identity and original exceptions', () => {
  const promise = Promise.resolve('done');
  const object = { count: 0, call() { this.count++; return promise; } };
  const original = object.call;
  const undo = hookMethod(object, 'call', () => { throw new Error('observer failed'); });
  assert.equal(object.call(), promise);
  assert.equal(object.count, 1);
  undo(); assert.equal(object.call, original);
  const failure = new Error('business error');
  const target = { call() { throw failure; } };
  hookMethod(target, 'call', () => {});
  assert.throws(() => target.call(), (e) => e === failure);
});
