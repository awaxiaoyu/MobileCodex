import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { CdpConnection, listLocalTargets } from './cdp.ts';
import { installRendererProbe } from '../adapters/renderer/probe.js';
import { BridgeError } from './errors.ts';
import { fields, nonempty } from './policy.ts';
import { threadView } from './views.ts';
import type { Backend, JsonObject } from './types.ts';

// Experimental in-process adapter. It only becomes connected after a read-only
// app-server request actually round-trips through the Desktop's own IPC.
export class RendererBackend extends EventEmitter implements Backend {
  id = `renderer_${randomUUID()}`;
  kind = 'desktop-shared' as const;
  generation = 1;
  status = 'stopped';
  methods = new Set(['bridge.model.list', 'bridge.thread.list', 'bridge.thread.read']);
  verifiedMethods = new Set<string>();
  options: { endpoint: string; targetId: string; hostId?: string; allowControl?: boolean };
  connection?: CdpConnection;
  poller?: NodeJS.Timeout;
  constructor(options: { endpoint: string; targetId: string; hostId?: string; allowControl?: boolean }) { super(); this.options = options; }
  async start() {
    this.status = 'connecting';
    const targets = await listLocalTargets(this.options.endpoint);
    const target = targets.find((t) => t.id === this.options.targetId);
    if (!target) throw new BridgeError('desktop.target_not_found', 'Select a listed Codex renderer target');
    this.connection = await CdpConnection.connect(target);
    try {
      await this.connection.evaluate(`(${installRendererProbe.toString()})(window, ${JSON.stringify({ allowControl: this.options.allowControl, hostId: this.options.hostId ?? 'local' })})`);
      await this.invoke('model/list', {});
      this.verifiedMethods.add('bridge.model.list');
      this.status = 'connected';
      if (this.options.allowControl) for (const method of ['codex.request', 'bridge.turn.start', 'bridge.turn.steer', 'bridge.turn.interrupt']) this.methods.add(method);
      const poll = async () => {
        if (this.status !== 'connected') return;
        try {
          const events = await this.connection!.evaluate('window.__mobileCodexProbe.drain()');
          for (const event of events ?? []) {
            if (event.kind === 'notification') this.emit('notification', { method: event.method, params: event.params });
            else this.emit('approval.observed', { method: event.method, threadId: event.threadId, turnId: event.turnId });
          }
          this.poller = setTimeout(poll, 250);
        } catch { this.status = 'disconnected'; this.emit('disconnected'); }
      };
      this.poller = setTimeout(poll, 250);
    } catch (error) { this.status = 'errored'; await this.close(); throw error; }
  }
  private invoke(method: string, params: JsonObject) {
    return this.connection!.evaluate(`window.__mobileCodexProbe.call(${JSON.stringify(method)}, ${JSON.stringify(params)})`);
  }
  async call(method: string, params: JsonObject) {
    if (this.status !== 'connected') throw new BridgeError('backend.disconnected', 'Renderer is not connected');
    if (method === 'bridge.thread.list') {
      fields(params, ['limit', 'cursor']);
      const result = await this.invoke('thread/list', params);
      this.verifiedMethods.add(method);
      return { threads: result.data.map(threadView), nextCursor: result.nextCursor };
    }
    if (method === 'bridge.thread.read') {
      fields(params, ['threadId']); nonempty(params.threadId, 'threadId');
      const result = await this.invoke('thread/read', { threadId: params.threadId, includeTurns: true });
      this.verifiedMethods.add(method); return { thread: threadView(result.thread) };
    }
    if (method.startsWith('turn/') && !this.options.allowControl) throw new BridgeError('policy.control_disabled', 'Renderer control was not enabled locally');
    const result = await this.invoke(method === 'bridge.model.list' ? 'model/list' : method, params);
    if (method === 'model/list') this.verifiedMethods.add('bridge.model.list');
    return result;
  }
  // No respond(): Desktop keeps approval ownership until response arbitration
  // is verified. Observing an approval is not permission to submit it twice.
  async close() {
    if (this.poller) clearTimeout(this.poller);
    try { await this.connection?.evaluate('window.__mobileCodexProbe?.dispose()'); } catch {}
    this.connection?.close(); this.status = 'stopped';
  }
}
