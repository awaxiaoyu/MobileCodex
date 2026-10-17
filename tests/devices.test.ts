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
    const loadedActive = new DeviceStore(file); await loadedActive.load();
    assert.equal(loadedActive.authenticate(device.token)?.id, device.deviceId);
    await loadedActive.markSeen(device.deviceId, '192.0.2.10');
    assert.equal(loadedActive.list()[0].lastSeenAt !== undefined, true);
    assert.equal(loadedActive.list()[0].lastAddress, '192.0.2.10');
    await loadedActive.updateName(device.deviceId, '  Pixel\u0000 9 Pro  ');
    assert.equal(loadedActive.list()[0].name, 'Pixel 9 Pro');
    await store.revoke(device.deviceId);
    assert.equal(store.list().some((entry) => entry.id === device.deviceId), false);
    const loaded = new DeviceStore(file); await loaded.load(); assert.equal(loaded.authenticate(device.token), undefined);
  } finally { await rm(root, { recursive: true, force: true }); }
});
