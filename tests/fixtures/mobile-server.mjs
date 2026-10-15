import { createInterface } from 'node:readline';
import { Bridge } from '../../src/bridge.ts';
import { DeviceStore } from '../../src/devices.ts';
import { createMobileServer } from '../../src/mobile-server.ts';
import { join } from 'node:path';

const root = process.argv[2];
const devices = new DeviceStore(join(root, 'devices.json')); await devices.load();
const mobile = createMobileServer(new Bridge(), devices, { cert: join(root, 'cert.pem'), key: join(root, 'key.pem') });
mobile.server.listen(0, '127.0.0.1', () => {
  const pairing = devices.beginPairing();
  console.log(JSON.stringify({ ...pairing, url: `wss://127.0.0.1:${mobile.server.address().port}/ws`, fingerprint: mobile.fingerprint }));
});
createInterface({ input: process.stdin }).on('line', async (line) => {
  if (line === 'revoke') for (const device of devices.list()) await devices.revoke(device.id);
  if (line === 'close') mobile.close();
});
process.once('SIGTERM', () => mobile.close());
