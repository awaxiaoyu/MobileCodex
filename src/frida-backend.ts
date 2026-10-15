import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createInterface } from 'node:readline';
import { resolve } from 'node:path';
import { BridgeError } from './errors.ts';
import { fields, nonempty } from './policy.ts';
import { threadView } from './views.ts';
import { validateNative } from './schema.ts';
import { fileURLToPath } from 'node:url';
import type { Backend, JsonObject, NativeId } from './types.ts';

type Pending = { resolve: (value: any) => void; reject: (error: unknown) => void; timer: NodeJS.Timeout };

/**
 * Desktop shared adapter using the checked-in Frida agent. The agent owns the
 * process attach and Main-thread N-API scheduling; this class only transports
 * registered operations and never accepts JavaScript source from the client.
 */
export class FridaBackend extends EventEmitter implements Backend {
  id = `frida_${randomUUID()}`;
  kind = 'desktop-shared' as const;
  generation = 1;
  status = 'stopped';
  methods = new Set(['bridge.model.list', 'bridge.project.list', 'bridge.thread.list', 'bridge.thread.read']);
  verifiedMethods = new Set<string>();
  private child?: ChildProcessWithoutNullStreams;
  private pending = new Map<string, Pending>();
  private poller?: NodeJS.Timeout;
  private draining = false;
  private serverRequests = new Map<NativeId, { method: string; threadId?: string }>();
  private models: any[] = [];
  private lastProbeSeq = 0;
  private projectRoots = new Map<string, string>();
  private options: { workspace: string; pid?: number; python?: string; deps?: string; timeoutMs?: number; allowControl?: boolean; projectProvider?: () => Promise<any> };
  lastCleanup?: { hooksRestored: boolean; stopped: boolean };

  constructor(options: { workspace: string; pid?: number; python?: string; deps?: string; timeoutMs?: number; allowControl?: boolean; projectProvider?: () => Promise<any> }) {
    super(); this.options = options;
  }

  async start() {
    this.status = 'connecting';
    const adapterRoot = fileURLToPath(new URL('..', import.meta.url));
    const script = resolve(adapterRoot, 'scripts', 'frida-bridge.py');
    this.child = spawn(this.options.python ?? process.env.MOBILE_CODEX_FRIDA_PYTHON ?? 'python', [script, '--workspace', adapterRoot, ...(this.options.pid ? ['--pid', String(this.options.pid)] : [])], {
      cwd: this.options.workspace,
      env: { ...process.env, ...(this.options.deps ? { MOBILE_CODEX_FRIDA_DEPS: this.options.deps } : {}) },
      windowsHide: true,
    });
    this.child.stderr.setEncoding('utf8');
    this.child.stderr.on('data', (chunk) => this.emit('diagnostic', String(chunk).slice(0, 2000)));
    const lines = createInterface({ input: this.child.stdout });
    lines.on('line', (line) => this.receiveLine(line));
    this.child.on('error', (error) => this.fail(error));
    this.child.on('exit', () => { if (this.status !== 'stopped') { this.status = 'disconnected'; this.fail(new BridgeError('backend.disconnected', 'Frida helper exited', true)); this.emit('disconnected'); } });
    try {
      await this.waitForReady();
      const installed = await this.send('install', { allowControl: this.options.allowControl === true, allowApprovals: this.options.allowControl === true });
      if (installed?.error) throw new BridgeError('desktop.inject_failed', installed.error);
      this.status = 'connected';
      await this.call('model/list', {});
      if (this.options.allowControl) for (const name of ['bridge.thread.create', 'bridge.thread.resume', 'bridge.turn.start', 'bridge.turn.steer', 'bridge.turn.interrupt', 'codex.request']) this.methods.add(name);
      this.verifiedMethods.add('bridge.model.list');
      this.poller = setInterval(() => { void this.drain(); }, 250);
    } catch (error) { await this.close(); this.status = 'errored'; throw error; }
  }

  private waitForReady() {
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete('__ready__'); reject(new BridgeError('desktop.inject_timeout', 'Frida helper did not attach to Desktop', true)); }, this.options.timeoutMs ?? 30_000);
      this.pending.set('__ready__', { resolve: () => { clearTimeout(timer); resolve(); }, reject, timer });
    });
  }

  private receiveLine(line: string) {
    let message: any;
    try { message = JSON.parse(line); } catch { return; }
    this.emit('transport.status', { type: message.type, stage: message.payload?.stage, phase: message.payload?.value?.phase, error: message.description ?? message.payload?.message });
    if (message.type === 'ready') { const pending = this.pending.get('__ready__'); if (pending) { this.pending.delete('__ready__'); clearTimeout(pending.timer); pending.resolve(true); } return; }
    if (message.type === 'detached' || message.type === 'agent-error' || message.payload?.stage === 'error') { this.fail(new BridgeError('desktop.inject_failed', message.description ?? message.payload?.message ?? 'Frida agent failed')); return; }
    if (message.type !== 'agent' || message.payload?.stage !== 'poll') return;
    for (const result of message.payload.value?.outbox ?? []) this.handleResult(result);
  }

  private handleResult(result: any) {
    if (!result?.id) return;
    const pending = this.pending.get(result.id);
    if (!pending) return;
    this.pending.delete(result.id); clearTimeout(pending.timer);
    if (result.ok) pending.resolve(result.result);
    else pending.reject(new BridgeError(/timed out|unknown|unloaded/i.test(result.error) ? 'backend.result_unknown' : 'desktop.request_failed', result.error));
  }

  private fail(error: unknown) {
    for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(error); }
    this.pending.clear();
  }

  private send(op: string, value: JsonObject) {
    if (!this.child || this.child.killed) return Promise.reject(new BridgeError('backend.disconnected', 'Frida helper is not running', true));
    const id = `frida-${randomUUID()}`;
    const timeout = this.options.timeoutMs ?? 30_000;
    return new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new BridgeError('backend.result_unknown', 'Desktop operation timed out; result is unknown', true)); }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.child!.stdin.write(JSON.stringify({ id, op, ...value }) + '\n', (error) => {
        if (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
      });
    });
  }

  private async drain() {
    if (this.status !== 'connected' || this.draining) return;
    this.draining = true;
    try {
      const result = await this.send('drain', {});
      for (const event of result?.events ?? []) {
        if (event.seq !== this.lastProbeSeq + 1) this.emit('events.gap');
        this.lastProbeSeq = event.seq;
        if (event.kind === 'notification') this.emit('notification', { method: event.method, params: event.params });
        else if (event.kind === 'server.request') { this.serverRequests.set(event.id, { method: event.method, threadId: event.params?.threadId }); this.emit('serverRequest', event); }
        else if (event.kind === 'server.request.observed') this.emit('approval.observed', event);
      }
      for (const hook of result?.hooks ?? []) if (hook.kind === 'approval.claimed') this.emit('serverRequest.claimed', hook);
    } catch { this.status = 'disconnected'; this.emit('disconnected'); }
    finally { this.draining = false; }
  }

  async flush() {
    while (this.draining) await new Promise((resolve) => setTimeout(resolve, 10));
    await this.drain();
  }

  async call(method: string, params: JsonObject) {
    if (this.status !== 'connected') throw new BridgeError('backend.disconnected', 'Desktop shared adapter is not connected');
    if (method === 'bridge.project.list') {
      fields(params, []);
      const result = this.options.projectProvider ? await this.options.projectProvider() : { projects: [] };
      const projects = (result.projects ?? []).filter((p: any) => p.projectKind === 'local' && p.hostId === 'local' && typeof p.path === 'string');
      this.projectRoots.clear(); this.projectRoots.set('workspace', this.options.workspace);
      for (const project of projects) this.projectRoots.set(project.projectId, project.path);
      return { projects: projects.length ? projects.map((p: any) => ({ projectId: p.projectId, label: p.label, hostId: p.hostId })) : [{ projectId: 'workspace', label: 'Bridge workspace', hostId: 'local' }] };
    }
    if (method === 'bridge.thread.list') { fields(params, ['limit', 'cursor']); const result = await this.send('call', { method: 'thread/list', params }); this.verifiedMethods.add('bridge.thread.list'); return { threads: (result.data ?? []).map(threadView), nextCursor: result.nextCursor }; }
    if (method === 'bridge.thread.read') { fields(params, ['threadId']); nonempty(params.threadId, 'threadId'); const result = await this.send('call', { method: 'thread/read', params: { threadId: params.threadId, includeTurns: true } }); this.verifiedMethods.add('bridge.thread.read'); return { thread: threadView(result.thread) }; }
    if (method === 'bridge.thread.create') {
      if (!this.options.allowControl) throw new BridgeError('policy.control_disabled', 'Thread creation is disabled');
      fields(params, ['projectId']);
      await this.call('bridge.project.list', {});
      const root = this.projectRoots.get(params.projectId);
      if (!root) throw new BridgeError('project.not_found', 'Select a project advertised by this Desktop');
      const native = { cwd: root, ...(params.projectId === 'workspace' ? {} : { projectId: params.projectId }) };
      validateNative('ThreadStartParams', native);
      const result = await this.send('call', { method: 'thread/start', params: native });
      this.verifiedMethods.add(method);
      return { thread: threadView(result.thread) };
    }
    if (method === 'bridge.thread.resume') {
      if (!this.options.allowControl) throw new BridgeError('policy.control_disabled', 'Thread resume is disabled');
      fields(params, ['threadId']); nonempty(params.threadId, 'threadId');
      validateNative('ThreadResumeParams', params);
      const result = await this.send('call', { method: 'thread/resume', params: { threadId: params.threadId, excludeTurns: true } });
      this.verifiedMethods.add(method);
      return { thread: threadView(result.thread), model: result.model, effort: result.reasoningEffort };
    }
    if (method.startsWith('turn/') && !this.options.allowControl) throw new BridgeError('policy.control_disabled', 'Desktop control was not enabled locally');
    if (method === 'turn/start' && (params.model || params.effort || params.collaborationMode)) {
      const selected = params.model ?? params.collaborationMode?.settings?.model;
      const model = this.models.find((m) => m.id === selected || m.model === selected) ?? (!selected ? this.models.find((m) => m.isDefault) : undefined);
      if (!model || model.hidden) throw new BridgeError('model.unavailable', 'Select a model advertised by the current Desktop');
      const effort = params.effort ?? params.collaborationMode?.settings?.reasoning_effort;
      if (effort && !(model.supportedReasoningEfforts ?? []).some((e: any) => e.reasoningEffort === effort)) throw new BridgeError('model.effort_unavailable', 'Reasoning effort is not supported by the selected model');
    }
    const result = await this.send('call', { method, params });
    if (method === 'model/list') this.models = result.data ?? [];
    if (method.startsWith('turn/')) this.verifiedMethods.add('bridge.' + method.replace('/', '.'));
    return result;
  }

  async respond(id: NativeId, result: unknown) {
    if (!this.options.allowControl) throw new BridgeError('policy.control_disabled', 'Desktop replies are disabled');
    const observed = this.serverRequests.get(id);
    if (!observed) throw new BridgeError('server_request.resolved', 'Unknown Desktop request');
    await this.send('respond', { nativeId: id, method: observed.method, result });
  }

  async close() {
    if (this.poller) clearInterval(this.poller);
    if (this.child && !this.child.killed) {
      try { this.lastCleanup = await this.send('shutdown', {}); } catch { /* helper may already be gone */ }
      this.status = 'stopped';
      this.child.kill();
    }
    this.fail(new BridgeError('backend.disconnected', 'Desktop shared adapter closed'));
    this.status = 'stopped';
  }
}
