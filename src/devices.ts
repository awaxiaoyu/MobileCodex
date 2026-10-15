import { EventEmitter } from 'node:events';
import { randomBytes, randomUUID, createHash, timingSafeEqual } from 'node:crypto';
import { readFile, mkdir, writeFile, rename } from 'node:fs/promises';
import { dirname } from 'node:path';
import { BridgeError } from './errors.ts';

type Device = { id: string; name: string; tokenHash: string; createdAt: string; revokedAt?: string };
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const same = (left: string, right: string) => { const a = Buffer.from(left); const b = Buffer.from(right); return a.length === b.length && timingSafeEqual(a, b); };

export class DeviceStore extends EventEmitter {
  private file: string;
  private devices: Device[] = [];
  private pairing?: { id: string; secretHash: string; expiresAt: number };
  private writes = Promise.resolve();
  constructor(file: string) { super(); this.file = file; }
  async load() {
    try { this.devices = JSON.parse(await readFile(this.file, 'utf8')); }
    catch (error: any) { if (error.code !== 'ENOENT') throw error; }
  }
  beginPairing() {
    const secret = randomBytes(32).toString('base64url');
    const id = randomUUID(); const expiresAt = Date.now() + 120000;
    this.pairing = { id, secretHash: hash(secret), expiresAt };
    return { id, secret, expiresAt: new Date(expiresAt).toISOString() };
  }
  async pair(id: string, secret: string, name: string) {
    const pairing = this.pairing;
    if (!pairing || pairing.id !== id || pairing.expiresAt < Date.now() || !same(pairing.secretHash, hash(secret))) throw new BridgeError('pairing.invalid', 'Pairing secret is invalid or expired');
    if (!name.trim() || name.length > 100) throw new BridgeError('protocol.invalid_params', 'Device name must be 1..100 characters');
    this.pairing = undefined; // Claim synchronously before persistence.
    const token = randomBytes(32).toString('base64url'); const deviceId = randomUUID();
    this.devices.push({ id: deviceId, name, tokenHash: hash(token), createdAt: new Date().toISOString() });
    await this.save();
    return { deviceId, token };
  }
  authenticate(token: string) { return this.devices.find((d) => !d.revokedAt && same(d.tokenHash, hash(token))); }
  list() { return this.devices.map(({ tokenHash, ...view }) => view); }
  async revoke(id: string) {
    const device = this.devices.find((d) => d.id === id);
    if (!device) throw new BridgeError('device.not_found', 'Unknown device');
    device.revokedAt = new Date().toISOString(); this.emit('revoked', id); await this.save();
  }
  private save() {
    this.writes = this.writes.then(async () => {
      await mkdir(dirname(this.file), { recursive: true });
      const temporary = this.file + '.tmp';
      await writeFile(temporary, JSON.stringify(this.devices, null, 2), { mode: 0o600 });
      await rename(temporary, this.file);
    });
    return this.writes;
  }
}
