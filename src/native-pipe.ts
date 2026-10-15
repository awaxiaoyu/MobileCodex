import { createConnection, type Socket } from 'node:net';
import { JsonRpc } from './json-rpc.ts';
import { BridgeError } from './errors.ts';

export const MAX_FRAME_BYTES = 8 * 1024 * 1024;
export function encodeFrame(message: any): Buffer {
  const body = Buffer.from(JSON.stringify(message));
  if (body.length > MAX_FRAME_BYTES) throw new BridgeError('protocol.message_too_large', 'NativePipe frame exceeds limit');
  const frame = Buffer.alloc(body.length + 4);
  frame.writeUInt32LE(body.length);
  body.copy(frame, 4);
  return frame;
}

export class FrameDecoder {
  buffer = Buffer.alloc(0);
  push(chunk: Buffer): any[] {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    const messages = [];
    while (this.buffer.length >= 4) {
      const length = this.buffer.readUInt32LE(0);
      if (length > MAX_FRAME_BYTES) throw new BridgeError('backend.invalid_frame', 'NativePipe frame exceeds limit');
      if (this.buffer.length < length + 4) break;
      messages.push(JSON.parse(this.buffer.subarray(4, length + 4).toString('utf8')));
      this.buffer = this.buffer.subarray(length + 4);
    }
    return messages;
  }
}

export class NativePipeClient {
  path: string;
  socket?: Socket;
  rpc?: JsonRpc;
  timeoutMs: number;
  connecting?: Promise<void>;
  constructor(path: string, timeoutMs = 5000) { this.path = path; this.timeoutMs = timeoutMs; }
  async connect() {
    if (this.socket && !this.socket.destroyed) return;
    if (this.connecting) return this.connecting;
    this.connecting = new Promise<void>((resolve, reject) => {
      const socket = createConnection(this.path);
      const timer = setTimeout(() => { socket.destroy(); reject(new BridgeError('desktop.connect_timeout', 'NativePipe connect timed out')); }, this.timeoutMs);
      socket.once('error', (error) => { clearTimeout(timer); reject(error); });
      socket.once('connect', () => {
        clearTimeout(timer);
        this.socket = socket;
        const decoder = new FrameDecoder();
        const rpc = new JsonRpc((message) => socket.write(encodeFrame({ jsonrpc: '2.0', ...message })), this.timeoutMs);
        this.rpc = rpc;
        socket.on('data', (chunk) => {
          try { for (const message of decoder.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk))) rpc.receive(message); }
          catch (error) { rpc.close(error as BridgeError); socket.destroy(); }
        });
        socket.on('error', () => rpc.close());
        socket.on('close', () => rpc.close());
        resolve();
      });
    });
    try { await this.connecting; } finally { this.connecting = undefined; }
  }
  async request(method: string, params?: any) { await this.connect(); return this.rpc!.request(method, params); }
  close() { this.rpc?.close(); this.socket?.destroy(); }
}
