import { EventEmitter } from 'node:events';
import { BridgeError } from './errors.ts';
import type { NativeId } from './types.ts';

export class JsonRpc extends EventEmitter {
  send: (message: any) => void;
  nextId = 1;
  pending = new Map<NativeId, { resolve: (value: any) => void; reject: (error: Error) => void; timer: NodeJS.Timeout }>();
  closed = false;
  timeoutMs: number;
  constructor(send: (message: any) => void, timeoutMs = 30_000) {
    super();
    this.send = send;
    this.timeoutMs = timeoutMs;
  }
  request(method: string, params: any = {}): Promise<any> {
    if (this.closed) return Promise.reject(new BridgeError('backend.disconnected', 'Backend is disconnected'));
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new BridgeError('backend.result_unknown', 'Backend request timed out; query state before retrying', false));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      try { this.send({ id, method, params }); }
      catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  receive(message: any) {
    if (!message || typeof message !== 'object') throw new BridgeError('backend.invalid_message', 'Invalid backend message');
    if (typeof message.method === 'string') {
      this.emit(message.id !== undefined ? 'serverRequest' : 'notification', message);
      return;
    }
    const pending = this.pending.get(message.id);
    if (!pending) return;
    this.pending.delete(message.id);
    clearTimeout(pending.timer);
    if (message.error) pending.reject(new BridgeError('codex.request_failed', message.error.message ?? 'Codex request failed', false, { nativeCode: message.error.code }));
    else if (Object.hasOwn(message, 'result')) pending.resolve(message.result);
    else pending.reject(new BridgeError('backend.invalid_message', 'Missing result/error'));
  }
  respond(id: NativeId, result: unknown) {
    if (this.closed) throw new BridgeError('backend.disconnected', 'Backend is disconnected');
    this.send({ id, result });
  }
  notify(method: string, params?: unknown) { this.send({ method, ...(params !== undefined ? { params } : {}) }); }
  close(error = new BridgeError('backend.result_unknown', 'Backend disconnected; pending result is unknown')) {
    if (this.closed) return;
    this.closed = true;
    for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(error); }
    this.pending.clear();
  }
}
