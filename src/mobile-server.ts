import { createServer } from 'node:https';
import { X509Certificate, createHash } from 'node:crypto';
import { readFileSync, createReadStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { WebSocketServer, WebSocket } from 'ws';
import { Bridge } from './bridge.ts';
import { DeviceStore } from './devices.ts';
import { BridgeError, errorPayload } from './errors.ts';

export function createMobileServer(bridge: Bridge, devices: DeviceStore, options: { cert: string; key: string }) {
  const certificate = readFileSync(options.cert);
  const fingerprint = createHash('sha256').update(new X509Certificate(certificate).raw).digest('hex');
  const sockets = new Map<WebSocket, string>();
  const reply = (res: any, status: number, value: any) => { res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(value)); };
  const authenticate = (req: any) => {
    if (req.headers.origin) throw new BridgeError('auth.origin_not_allowed', 'Browser origins are disabled');
    const token = /^Bearer (.+)$/.exec(req.headers.authorization ?? '')?.[1];
    const device = token && devices.authenticate(token);
    if (!device) throw new BridgeError('auth.required', 'Paired device token required');
    const deviceName = req.headers['x-mobile-device-name'];
    if (typeof deviceName === 'string') void devices.updateName(device.id, deviceName).catch(() => {});
    void devices.markSeen(device.id, req.socket.remoteAddress).catch(() => {});
    return device;
  };
  const server = createServer({ cert: certificate, key: readFileSync(options.key), minVersion: 'TLSv1.2' }, async (req, res) => {
    try {
      if (req.headers.origin) return reply(res, 403, { error: { code: 'auth.origin_not_allowed' } });
      if (req.method === 'POST' && req.url === '/pair') {
        let input = ''; for await (const chunk of req) { input += chunk; if (Buffer.byteLength(input) > 4096) throw new BridgeError('protocol.message_too_large', 'Pairing input is too large'); }
        const body = JSON.parse(input); if (![body.id, body.secret, body.name].every((s) => typeof s === 'string')) throw new BridgeError('protocol.invalid_params', 'Pairing id, secret and name are required');
        return reply(res, 200, await devices.pair(body.id, body.secret, body.name));
      }
      authenticate(req);
      if (req.method === 'GET' && req.url?.startsWith('/artifacts/')) {
        const url = new URL(req.url, 'https://localhost');
        const backendId = url.searchParams.get('backendId') ?? ''; const generation = Number(url.searchParams.get('generation')); const threadId = url.searchParams.get('threadId') ?? '';
        if (!bridge.artifacts || bridge.backends.get(backendId)?.generation !== generation) throw new BridgeError('artifact.not_found', 'Task artifact backend is unavailable');
        const artifact = await bridge.artifacts.get(url.pathname.slice(11), backendId, generation, threadId);
        res.writeHead(200, { 'content-type': artifact.contentType, 'content-disposition': `attachment; filename*=UTF-8''${encodeURIComponent(artifact.name)}`, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
        await pipeline(createReadStream(artifact.path), res); return;
      }
      reply(res, 404, { error: { code: 'http.not_found' } });
    } catch (error) { if (!res.headersSent) reply(res, error instanceof BridgeError ? 403 : 400, { error: errorPayload(error) }); else res.destroy(); }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4 * 1024 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    try {
      if (req.url !== '/ws') throw new BridgeError('http.not_found', 'WebSocket endpoint not found');
      const device = authenticate(req);
      wss.handleUpgrade(req, socket, head, (ws) => { sockets.set(ws, device.id); devices.setConnected(device.id, true); wss.emit('connection', ws); });
    } catch { socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); }
  });
  const send = (ws: WebSocket, value: any) => {
    if (ws.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > 8 * 1024 * 1024) { ws.close(1013, 'Client fell behind; reconnect and resume'); return; }
    ws.send(JSON.stringify(value));
  };
  wss.on('connection', (ws) => {
    send(ws, { v: 1, kind: 'event', method: 'event.connection.ready', payload: { deviceId: sockets.get(ws), capabilities: bridge.capabilities() } });
    ws.on('message', async (bytes) => {
      try { const message = JSON.parse(bytes.toString()); send(ws, await bridge.handle(message)); }
      catch (error) { send(ws, { v: 1, kind: 'error', method: 'protocol.error', payload: errorPayload(error) }); }
    });
    const disconnect = () => {
      const deviceId = sockets.get(ws);
      sockets.delete(ws);
      if (deviceId && ![...sockets.values()].includes(deviceId)) devices.setConnected(deviceId, false);
    };
    ws.on('close', disconnect);
    ws.on('error', disconnect);
  });
  const broadcast = (event: any) => { for (const socket of sockets.keys()) send(socket, event); };
  const revoke = (id: string) => { for (const [socket, deviceId] of sockets) if (deviceId === id) { sockets.delete(socket); socket.close(1008, 'Device revoked'); } };
  bridge.on('event', broadcast); devices.on('revoked', revoke);
  const heartbeat = setInterval(() => { for (const socket of sockets.keys()) socket.ping(); }, 25000); heartbeat.unref();
  server.on('close', () => { clearInterval(heartbeat); bridge.off('event', broadcast); devices.off('revoked', revoke); for (const [socket, deviceId] of sockets) { devices.setConnected(deviceId, false); socket.terminate(); } sockets.clear(); wss.close(); });
  return { server, fingerprint, close() { for (const socket of sockets.keys()) socket.terminate(); server.close(); } };
}
