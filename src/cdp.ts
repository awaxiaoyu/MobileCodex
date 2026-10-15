import { JsonRpc } from './json-rpc.ts';
import { BridgeError } from './errors.ts';

export async function listLocalTargets(endpoint: string) {
  const base = new URL(endpoint);
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname) || base.protocol !== 'http:') throw new Error('Only a local HTTP CDP endpoint is supported');
  let response: Response;
  try { response = await fetch(new URL('/json/list', base), { signal: AbortSignal.timeout(5000) }); }
  catch { throw new BridgeError('desktop.debug_endpoint_unavailable', 'Local Desktop CDP endpoint is unavailable; no adapter was injected'); }
  if (!response.ok) throw new Error('CDP target list request failed');
  const targets: any[] = await response.json();
  return targets.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl);
}

// Local developer instrumentation transport only. This endpoint is never
// relayed to mobile and callers cannot supply arbitrary runtime expressions.
export class CdpConnection {
  socket: WebSocket;
  rpc: JsonRpc;
  private constructor(socket: WebSocket) {
    this.socket = socket;
    this.rpc = new JsonRpc((message) => socket.send(JSON.stringify(message)), 20_000);
    socket.addEventListener('message', (event) => this.rpc.receive(JSON.parse(String(event.data))));
    socket.addEventListener('close', () => this.rpc.close());
  }
  static async connect(target: any) {
    const url = new URL(target.webSocketDebuggerUrl);
    if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.protocol !== 'ws:') throw new Error('CDP WebSocket must be local');
    const socket = new WebSocket(url);
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { socket.close(); reject(new Error('CDP connection timed out')); }, 5000);
      socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
      socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('CDP connection failed')); }, { once: true });
    });
    return new CdpConnection(socket);
  }
  async evaluate(expression: string) {
    const result = await this.rpc.request('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (result.exceptionDetails) {
      const message = result.exceptionDetails.exception?.description ?? 'Renderer operation failed';
      throw new BridgeError(message.includes('result is unknown') ? 'backend.result_unknown' : 'desktop.request_failed', message);
    }
    return result.result?.value;
  }
  close() { this.rpc.close(); this.socket.close(); }
}
