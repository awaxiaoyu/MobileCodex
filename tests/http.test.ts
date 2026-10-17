import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { Bridge } from '../src/bridge.ts';
import { createHttpServer } from '../src/http.ts';
import { DeviceStore } from '../src/devices.ts';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('loopback HTTP requires bearer and rejects browser origin', async () => {
  const token = 'x'.repeat(40);
  const server = createHttpServer(new Bridge(), token);
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = 'http://127.0.0.1:' + (server.address() as any).port;
  try {
    assert.equal((await fetch(url + '/capabilities')).status, 401);
    const auth = { authorization: 'Bearer ' + token };
    assert.equal((await fetch(url + '/capabilities', { headers: auth })).status, 200);
    assert.equal((await fetch(url + '/capabilities', { headers: { ...auth, origin: 'https://example.test' } })).status, 403);
    const reply = await fetch(url + '/rpc', { method: 'POST', headers: auth, body: JSON.stringify({ v: 1, id: 'list', kind: 'request', method: 'bridge.backends.list', payload: {} }) });
    assert.equal((await reply.json()).kind, 'response');
  } finally { await new Promise<void>((resolve) => server.close(() => resolve())); }
});

test('Desktop settings UI session exposes redacted status and pairing only on loopback', async () => {
  const token = 'x'.repeat(40);
  const ui = 'u'.repeat(40);
  const server = createHttpServer(new Bridge(), token, undefined, { token: ui, status: () => ({ bridge: { status: 'running' }, secret: undefined }) });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = 'http://127.0.0.1:' + (server.address() as any).port;
  try {
    const ok = await fetch(url + '/ui/status', { headers: { 'X-Mobile-Codex-UI-Session': ui } });
    assert.equal(ok.status, 200);
    assert.deepEqual((await ok.json()).bridge.status, 'running');
    assert.equal((await fetch(url + '/ui/status')).status, 401);
    assert.equal((await fetch(url + '/ui/status', { headers: { authorization: 'Bearer ' + token } })).status, 404);
    const preflight = await fetch(url + '/ui/status', { method: 'OPTIONS', headers: { origin: 'app://codex', 'access-control-request-method': 'GET', 'access-control-request-headers': 'X-Mobile-Codex-UI-Session' } });
    assert.equal(preflight.status, 204);
    const browser = await fetch(url + '/ui/status', { headers: { origin: 'app://codex', 'X-Mobile-Codex-UI-Session': ui } });
    assert.equal(browser.headers.get('access-control-allow-origin'), 'app://codex');
    assert.equal(browser.headers.get('access-control-allow-private-network'), 'true');
    const opaque = await fetch(url + '/ui/status', { headers: { origin: 'null', 'X-Mobile-Codex-UI-Session': ui } });
    assert.equal(opaque.status, 200);
    assert.equal(opaque.headers.get('access-control-allow-origin'), 'null');
  } finally { await new Promise<void>((resolve) => server.close(() => resolve())); }
});

test('Desktop settings pairing accepts async QR payloads', async () => {
  const token = 'x'.repeat(40); const ui = 'u'.repeat(40);
  const root = await mkdtemp(join(tmpdir(), 'mobile-codex-http-'));
  const devices = new DeviceStore(join(root, 'devices.json')); await devices.load();
  const server = createHttpServer(new Bridge(), token, devices, { token: ui, pairing: async () => ({ id: 'pair', secret: 'one-use', url: 'wss://host/ws', fingerprint: 'f'.repeat(64), qr: 'data:image/png;base64,qr' }) });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try {
    const reply = await fetch('http://127.0.0.1:' + (server.address() as any).port + '/ui/pairing', { method: 'POST', headers: { 'X-Mobile-Codex-UI-Session': ui } });
    assert.equal(reply.status, 200);
    assert.equal((await reply.json()).qr, 'data:image/png;base64,qr');
  } finally { await new Promise<void>((resolve) => server.close(() => resolve())); }
});

test('expired Desktop settings session is rejected', async () => {
  const token = 'x'.repeat(40); const ui = 'u'.repeat(40);
  const server = createHttpServer(new Bridge(), token, undefined, { token: ui, expiresAt: Date.now() - 1 });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try { assert.equal((await fetch('http://127.0.0.1:' + (server.address() as any).port + '/ui/status', { headers: { 'X-Mobile-Codex-UI-Session': ui } })).status, 401); }
  finally { await new Promise<void>((resolve) => server.close(() => resolve())); }
});
