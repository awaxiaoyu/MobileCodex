import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { installRendererProbe, detectSettingsCapability, installBridgeSettingsUi, featureToggleState } from '../adapters/renderer/probe.js';
import { hookMethod } from '../adapters/renderer/hook.js';
import { extractRendererInstall } from '../src/frida-backend.ts';

test('Frida backend unwraps the renderer install result envelope', () => {
  const nested = { settings: { installed: true, deferred: true } };
  assert.equal(extractRendererInstall({ shellUrl: 'app://-/index.html', install: nested }), nested);
  assert.equal(extractRendererInstall(nested), nested);
});

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

test('renderer policy switches expose effective control and approval state', () => {
  const win: any = new EventTarget();
  win.crypto = { randomUUID };
  win.electronBridge = {
    getDesktopUserAgent: () => 'Codex Desktop/26.1007.21434 (Windows NT 10.0; x64)',
    sendMessageFromView() { return Promise.resolve({}); },
  };
  installRendererProbe(win, { allowControl: true, allowApprovals: true });
  assert.equal(win.__mobileCodexProbe.status().allowControl, true);
  assert.equal(win.__mobileCodexProbe.setPolicy('allow-control', false).allowControl, false);
  assert.equal(win.__mobileCodexProbe.setPolicy('approval-forwarding', false).allowApprovals, false);
  assert.throws(() => win.__mobileCodexProbe.setPolicy('unknown', true), /Unsupported renderer policy/);
  win.__mobileCodexProbe.dispose();
});

test('renderer refuses unsupported versions and does not install', () => {
  const win = { electronBridge: { sendMessageFromView() {}, getDesktopUserAgent: () => 'Codex Desktop/unknown' } };
  assert.throws(() => installRendererProbe(win), /Unsupported Desktop version/);
});

test('settings UI capability fails closed without Desktop settings DOM', () => {
  assert.deepEqual(detectSettingsCapability({}), { supported: false, code: 'renderer_dom_unavailable', reason: 'Desktop settings DOM is unavailable' });
  const win: any = { electronBridge: { getDesktopUserAgent: () => 'Codex Desktop/26.1007.21434 (Windows NT; x64)' } };
  assert.equal(installBridgeSettingsUi(win, { endpoint: 'http://127.0.0.1:1', token: 'session' }).installed, false);
});

test('settings feature state keeps runtime switches interactive and startup-only switches disabled', () => {
  assert.deepEqual(featureToggleState({ enabled: true, editable: true, reason: '实时生效' }), { checked: true, disabled: false, title: '实时生效' });
  assert.deepEqual(featureToggleState({ enabled: false, editable: false, reason: '启动 Bridge 时需要 --allow-control' }), { checked: false, disabled: true, title: '启动 Bridge 时需要 --allow-control' });
});

test('settings capability recognizes a reusable native menu structure', () => {
  const item = { textContent: 'General', querySelectorAll: () => [] };
  const menu = { textContent: 'General Appearance', querySelectorAll: () => [item] };
  const capability = detectSettingsCapability({ document: { querySelectorAll: () => [menu] } });
  assert.equal(capability.supported, true);
  assert.equal(capability.template, item);
});

test('settings capability recognizes shortcut labels and finds Help anchor', () => {
  const setting = { textContent: '设置 Ctrl+,', parentElement: undefined as any };
  const help = { textContent: '帮助 >', parentElement: undefined as any };
  const menu = { textContent: '设置 Ctrl+, 帮助 >', parentElement: undefined as any, querySelectorAll: () => [setting, help] };
  setting.parentElement = menu; help.parentElement = menu;
  const capability = detectSettingsCapability({ document: { querySelectorAll: () => [setting, help] } });
  assert.equal(capability.supported, true);
  assert.equal(capability.help, help);
});

test('settings capability prefers labeled popup over a broad aside shell', () => {
  const setting = { textContent: '设置 Ctrl+,', parentElement: undefined as any };
  const help = { textContent: '帮助 >', parentElement: undefined as any };
  const popup = { textContent: '设置 Ctrl+, 帮助 >', parentElement: undefined as any, querySelectorAll: () => [setting, help] };
  const aside = { textContent: '设置 General Appearance', querySelectorAll: () => [{ textContent: 'General' }] };
  setting.parentElement = popup; help.parentElement = popup;
  const capability = detectSettingsCapability({ document: { querySelectorAll: () => [aside, setting, help] } });
  assert.equal(capability.menu, popup);
  assert.equal(capability.template, setting);
  assert.equal(capability.help, help);
});

test('settings capability defers when the account menu is closed', () => {
  const capability = detectSettingsCapability({ document: { querySelectorAll: () => [] } });
  assert.equal(capability.supported, true);
  assert.equal(capability.deferred, true);
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
