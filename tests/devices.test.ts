import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DeviceStore } from '../src/devices.ts';

test('pairing is one-use, tokens are hashed and revocation persists', async () => {
  const root = await mkdtemp(join(tmpdir(), 'mobile-pair-'));
  try {
    const file = join(root, 'devices.json'); const store = new DeviceStore(file); await store.load();
    const pairing = store.beginPairing();
    await assert.rejects(store.pair(pairing.id, 'wrong', 'phone'));
    const device = await store.pair(pairing.id, pairing.secret, 'phone');
    await assert.rejects(store.pair(pairing.id, pairing.secret, 'another'));
    assert.equal(store.authenticate(device.token)?.id, device.deviceId);
    assert.equal((await readFile(file, 'utf8')).includes(device.token), false);
    await store.revoke(device.deviceId);
    const loaded = new DeviceStore(file); await loaded.load(); assert.equal(loaded.authenticate(device.token), undefined);
  } finally { await rm(root, { recursive: true, force: true }); }
});
