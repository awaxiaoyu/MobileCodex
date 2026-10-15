import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { Bridge } from '../src/bridge.ts';
import { createHttpServer } from '../src/http.ts';

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
