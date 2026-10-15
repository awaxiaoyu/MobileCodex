import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { Bridge } from './bridge.ts';
import { errorPayload, BridgeError } from './errors.ts';
import { createReadStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import type { DeviceStore } from './devices.ts';

function json(response: ServerResponse, status: number, value: unknown) {
  const body = JSON.stringify(value);
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(body), 'cache-control': 'no-store' });
  response.end(body);
}
async function body(request: IncomingMessage) {
  const chunks: Buffer[] = []; let bytes = 0;
  for await (const chunk of request) { bytes += chunk.length; if (bytes > 4 * 1024 * 1024) throw new BridgeError('protocol.message_too_large', 'HTTP request exceeds limit'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}
export function createHttpServer(bridge: Bridge, token: string, devices?: DeviceStore) {
  if (token.length < 32) throw new Error('HTTP token must contain at least 32 characters');
  const subscribers = new Set<ServerResponse>();
  bridge.on('event', (event) => {
    const line = `data: ${JSON.stringify(event)}\n\n`;
    for (const response of subscribers) { try { response.write(line); } catch { subscribers.delete(response); } }
  });
  return createServer(async (request, response) => {
    try {
      if (request.method === 'GET' && request.url === '/health') return json(response, 200, { ok: true, protocol: 'mobile-codex-bridge/v1' });
      const actual = Buffer.from(request.headers.authorization ?? '');
      const expected = Buffer.from(`Bearer ${token}`);
      if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return json(response, 401, { error: { code: 'auth.required', message: 'Local bearer token required' } });
      // P0 is a CLI/local process endpoint. Browser origins are not accepted;
      // device pairing, browser/mobile CORS and WSS belong to the next stage.
      if (request.headers.origin) return json(response, 403, { error: { code: 'auth.origin_not_allowed', message: 'Browser origins are disabled in P0' } });
      if (devices && request.method === 'POST' && request.url === '/pairing') return json(response, 200, devices.beginPairing());
      if (devices && request.method === 'GET' && request.url === '/devices') return json(response, 200, { devices: devices.list() });
      if (devices && request.method === 'POST' && request.url === '/devices/revoke') { const input = await body(request); await devices.revoke(input.deviceId); return json(response, 200, { revoked: true }); }
      if (request.method === 'GET' && request.url === '/capabilities') return json(response, 200, bridge.capabilities());
      if (request.method === 'GET' && request.url?.startsWith('/artifacts/')) {
        const url = new URL(request.url, 'http://127.0.0.1');
        const backendId = url.searchParams.get('backendId') ?? '';
        const generation = Number(url.searchParams.get('generation'));
        const threadId = url.searchParams.get('threadId') ?? '';
        const backend = bridge.backends.get(backendId);
        if (!backend || backend.generation !== generation || !bridge.artifacts) throw new BridgeError('artifact.not_found', 'Task artifact backend is unavailable');
        const record = await bridge.artifacts.get(url.pathname.slice('/artifacts/'.length), backendId, generation, threadId);
        response.writeHead(200, { 'content-type': record.contentType, 'content-disposition': `attachment; filename*=UTF-8''${encodeURIComponent(record.name)}`, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
        await pipeline(createReadStream(record.path), response); return;
      }
      if (request.method === 'GET' && request.url === '/events') {
        response.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-cache', connection: 'keep-alive' });
        subscribers.add(response); response.on('close', () => subscribers.delete(response)); response.write(': connected\n\n'); return;
      }
      if (request.method === 'POST' && request.url === '/rpc') return json(response, 200, await bridge.handle(await body(request)));
      json(response, 404, { error: { code: 'http.not_found', message: 'Not found', retryable: false } });
    } catch (error) { if (!response.headersSent) json(response, error instanceof SyntaxError ? 400 : 500, { kind: 'error', payload: errorPayload(error) }); else response.destroy(); }
  });
}
