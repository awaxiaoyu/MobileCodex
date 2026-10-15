import test from 'node:test';
import assert from 'node:assert/strict';
import { request } from 'node:https';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { DeviceStore } from '../src/devices.ts';
import { createMobileServer } from '../src/mobile-server.ts';
import { Bridge } from '../src/bridge.ts';

test('WSS rejects unpaired clients, round-trips RPC and closes revoked devices', async () => {
  const root = await mkdtemp(join(tmpdir(), 'mobile-wss-'));
  const key = join(root, 'key.pem'); const cert = join(root, 'cert.pem');
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=localhost'], { stdio: 'ignore', windowsHide: true });
  const devices = new DeviceStore(join(root, 'devices.json')); await devices.load();
  const mobile = createMobileServer(new Bridge(), devices, { cert, key });
  mobile.server.listen(0, '127.0.0.1'); await once(mobile.server, 'listening');
  const port = (mobile.server.address() as any).port;
  try {
    const unauthorized = new WebSocket(`wss://127.0.0.1:${port}/ws`, { rejectUnauthorized: false });
    await once(unauthorized, 'error');
    const pairing = devices.beginPairing();
    const response: any = await new Promise((resolve, reject) => {
      const req = request({ hostname: '127.0.0.1', port, path: '/pair', method: 'POST', rejectUnauthorized: false }, (res) => { let text = ''; res.on('data', (c) => text += c); res.on('end', () => resolve(JSON.parse(text))); });
      req.on('error', reject); req.end(JSON.stringify({ ...pairing, name: 'test phone' }));
    });
    const ws = new WebSocket(`wss://127.0.0.1:${port}/ws`, { rejectUnauthorized: false, headers: { authorization: `Bearer ${response.token}` } });
    const ready = once(ws, 'message'); await once(ws, 'open'); await ready;
    const received = once(ws, 'message'); ws.send(JSON.stringify({ v: 1, kind: 'request', id: 'r', method: 'bridge.backends.list', payload: {} }));
    assert.equal(JSON.parse((await received)[0].toString()).id, 'r');
    const closed = once(ws, 'close'); await devices.revoke(response.deviceId); assert.equal((await closed)[0], 1008);
  } finally { mobile.close(); await once(mobile.server, 'close'); await rm(root, { recursive: true, force: true }); }
});
