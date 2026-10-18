import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createInterface } from 'node:readline';
import { resolve } from 'node:path';
import { BridgeError } from './errors.ts';
import { fields, nonempty } from './policy.ts';
import { mergeThreadViews, threadView } from './views.ts';
import { validateNative } from './schema.ts';
import { fileURLToPath } from 'node:url';
import type { Backend, JsonObject, NativeId } from './types.ts';

type Pending = { resolve: (value: any) => void; reject: (error: unknown) => void; timer: NodeJS.Timeout };

// The renderer command returns an envelope with shell metadata and the probe
// install result nested under `install`. Keep accepting the direct shape used
// by older helpers so a helper/bridge version mismatch fails safely.
export function extractRendererInstall(value: any) {
  return value?.install && typeof value.install === 'object' ? value.install : value;
}

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
  private recovering = false;
  private reconnectTimer?: NodeJS.Timeout;
  private reconnectAttempt = 0;
  private serverRequests = new Map<NativeId, { method: string; threadId?: string }>();
  private models: any[] = [];
  private lastProbeSeq = 0;
  private projectRoots = new Map<string, string>();
  private options: { workspace: string; pid?: number; python?: string; deps?: string; timeoutMs?: number; allowControl?: boolean; projectProvider?: () => Promise<any>; threadProvider?: (params?: JsonObject) => Promise<any>; settingsUi?: { endpoint: string; token: string }; settingsRequest?: (action: string, payload: JsonObject) => Promise<unknown> | unknown };
  lastCleanup?: { hooksRestored: boolean; stopped: boolean };
  private hooksInstalled = false;
  private hooksRestored = false;
  private helperPid?: number;
  private lastDiagnostic?: string;
  private settingsUiStatus: Record<string, any> = { installed: false, reason: 'not-requested' };
  private rendererInfo: { shellUrl?: string; userAgent?: string; settingsRequest?: Record<string, unknown> } = {};
  private helperVersions: { python?: string; frida?: string } = {};
  private runtimeFeatures: { allowControl: boolean; allowApprovals: boolean };

  constructor(options: { workspace: string; pid?: number; python?: string; deps?: string; timeoutMs?: number; allowControl?: boolean; projectProvider?: () => Promise<any>; threadProvider?: (params?: JsonObject) => Promise<any>; settingsUi?: { endpoint: string; token: string }; settingsRequest?: (action: string, payload: JsonObject) => Promise<unknown> | unknown }) {
    super(); this.options = options;
    this.runtimeFeatures = { allowControl: options.allowControl === true, allowApprovals: options.allowControl === true };
  }

  async start() {
    this.status = 'connecting';
    const adapterRoot = process.env.MOBILE_CODEX_APP_ROOT ?? fileURLToPath(new URL('..', import.meta.url));
    const script = resolve(adapterRoot, 'scripts', 'frida-bridge.py');
    const child = spawn(this.options.python ?? process.env.MOBILE_CODEX_FRIDA_PYTHON ?? 'python', [script, '--workspace', adapterRoot, ...(this.options.pid ? ['--pid', String(this.options.pid)] : [])], {
      cwd: this.options.workspace,
      env: { ...process.env, ...(this.options.deps ? { MOBILE_CODEX_FRIDA_DEPS: this.options.deps } : {}) },
      windowsHide: true,
    });
    this.child = child;
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => { if (this.child === child) { this.lastDiagnostic = String(chunk).slice(0, 2000); this.emit('diagnostic', this.lastDiagnostic); } });
    this.helperPid = child.pid;
    const lines = createInterface({ input: child.stdout });
    lines.on('line', (line) => this.receiveLine(line));
    child.on('error', (error) => { if (this.child === child) this.fail(error); });
    child.on('exit', () => {
      if (this.child !== child || this.status === 'stopped') return;
      this.status = 'disconnected';
      this.fail(new BridgeError('backend.disconnected', 'Frida helper exited', true));
      void this.recoverFromTransportFailure();
    });
    try {
      await this.waitForReady();
      const installed = await this.send('install', { allowControl: this.runtimeFeatures.allowControl, allowApprovals: this.runtimeFeatures.allowApprovals, settingsUi: this.options.settingsUi ?? null });
      const rendererInstall = extractRendererInstall(installed);
      if (installed?.error || rendererInstall?.error) throw new BridgeError('desktop.inject_failed', installed?.error ?? rendererInstall.error);
      this.hooksInstalled = rendererInstall?.settings?.installed !== false;
      this.settingsUiStatus = rendererInstall?.settings ?? { installed: false, reason: 'renderer did not return settings capability' };
      this.rendererInfo = {
        shellUrl: installed?.shellUrl,
        userAgent: installed?.userAgent,
        // Do not synchronously ask the renderer to make a settings request
        // while the install command is still being handled.  The renderer
        // needs the Main hook's response path to run, so doing that here
        // deadlocks the helper startup and makes the UI report a timeout.
        // The actual capability is exercised lazily when the user opens the
        // Bridge settings dialog.
        settingsRequest: { ok: true, transport: 'desktop-main-hook', lazy: true },
      };
      this.hooksRestored = false;
      this.status = 'connected';
      await this.call('model/list', {});
      if (this.runtimeFeatures.allowControl) this.enableControlMethods();
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
    if (message.type === 'ready') { this.helperPid = message.pid ?? this.helperPid; this.helperVersions = { python: message.pythonVersion, frida: message.fridaVersion }; const pending = this.pending.get('__ready__'); if (pending) { this.pending.delete('__ready__'); clearTimeout(pending.timer); pending.resolve(true); } return; }
    if (message.type === 'detached' || message.type === 'agent-error' || message.payload?.stage === 'error') { this.fail(new BridgeError('desktop.inject_failed', message.description ?? message.payload?.message ?? 'Frida agent failed')); return; }
    if (message.type !== 'agent' || message.payload?.stage !== 'poll') return;
    for (const result of message.payload.value?.outbox ?? []) this.handleResult(result);
  }

  private handleResult(result: any) {
    if (result?.kind === 'settings.request' && typeof result.requestId === 'string') { void this.handleSettingsRequest(result); return; }
    if (!result?.id) return;
    const pending = this.pending.get(result.id);
    if (!pending) return;
    this.pending.delete(result.id); clearTimeout(pending.timer);
    if (result.ok) pending.resolve(result.result);
    else pending.reject(new BridgeError(/timed out|unknown|unloaded/i.test(result.error) ? 'backend.result_unknown' : 'desktop.request_failed', result.error));
  }

  private async handleSettingsRequest(request: { requestId: string; action: string; payload?: JsonObject }) {
    try {
      if (!this.options.settingsRequest) throw new BridgeError('capability.unavailable', 'Desktop settings provider is unavailable');
      const payload = await this.options.settingsRequest(request.action, request.payload ?? {});
      await this.send('settings-response', { requestId: request.requestId, payload: payload as any });
    } catch (error) {
      try { await this.send('settings-response', { requestId: request.requestId, error: error instanceof Error ? error.message : String(error) }); } catch { /* renderer request will time out and show a bounded error */ }
    }
  }

  private enableControlMethods() {
    for (const name of ['bridge.thread.create', 'bridge.thread.resume', 'bridge.turn.start', 'bridge.turn.steer', 'bridge.turn.interrupt', 'codex.request']) this.methods.add(name);
  }

  async setFeature(name: string, enabled: boolean) {
    if (!['allow-control', 'approval-forwarding'].includes(name)) throw new BridgeError('protocol.invalid_params', 'Unsupported Bridge feature');
    if (enabled && this.options.allowControl !== true) throw new BridgeError('policy.control_disabled', 'Control must be enabled when Bridge starts before it can be enabled here');
    if (this.status !== 'connected') throw new BridgeError('backend.disconnected', 'Desktop shared adapter is not connected');
    const result = await this.send('settings-feature', { feature: name, enabled });
    if (result?.allowControl !== undefined) this.runtimeFeatures.allowControl = result.allowControl === true;
    if (result?.allowApprovals !== undefined) this.runtimeFeatures.allowApprovals = result.allowApprovals === true;
    if (this.runtimeFeatures.allowControl) this.enableControlMethods();
    else for (const method of ['bridge.thread.create', 'bridge.thread.resume', 'bridge.turn.start', 'bridge.turn.steer', 'bridge.turn.interrupt', 'codex.request']) this.methods.delete(method);
    return result;
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
    } catch (error) {
      this.lastDiagnostic = error instanceof Error ? error.message : String(error);
      await this.recoverFromTransportFailure();
    }
    finally { this.draining = false; }
  }

  private async recoverFromTransportFailure() {
    if (this.recovering || this.status === 'stopped' || this.status === 'errored') return;
    this.recovering = true;
    this.status = 'disconnected';
    this.emit('disconnected');
    const child = this.child;
    if (this.poller) clearInterval(this.poller);
    this.poller = undefined;
    this.fail(new BridgeError('backend.disconnected', 'Desktop shared adapter transport failed', true));
    try {
      if (child && child.exitCode === null) {
        const exited = new Promise<void>((resolve) => child.once('exit', () => resolve()));
        child.kill();
        await Promise.race([exited, new Promise<void>((resolve) => setTimeout(resolve, 3000))]);
      }
    } catch { /* process may already have exited */ }
    if (this.child === child) this.child = undefined;
    this.generation++;
    try {
      await this.start();
      this.reconnectAttempt = 0;
      this.emit('connected');
    } catch (error) {
      this.lastDiagnostic = error instanceof Error ? error.message : String(error);
      this.status = 'disconnected';
      this.emit('disconnected');
      const delays = [1_000, 2_000, 5_000, 10_000, 30_000];
      const delay = delays[Math.min(this.reconnectAttempt++, delays.length - 1)];
      this.reconnectTimer = setTimeout(() => { this.reconnectTimer = undefined; void this.recoverFromTransportFailure(); }, delay);
    } finally {
      this.recovering = false;
    }
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
      const rawProjects = Array.isArray(result?.projects) ? result.projects : [];
      const projects = rawProjects
        .map((p: any) => {
          const projectId = p.projectId ?? p.id ?? p.slug ?? p.path;
          const path = p.path ?? p.root ?? p.cwd;
          const label = p.label ?? p.name ?? p.title ?? (typeof path === 'string' ? path.split(/[\\/]/).at(-1) : projectId);
          const branch = p.branch ?? p.branchName ?? p.gitBranch;
          return { projectId, path, label, ...(branch ? { branch } : {}), hostId: p.hostId ?? 'local' };
        })
        .filter((p: any) => typeof p.projectId === 'string' && (p.hostId === 'local' || typeof p.path === 'string'));
      this.projectRoots.clear(); this.projectRoots.set('workspace', this.options.workspace);
      for (const project of projects) {
        if (typeof project.path === 'string') this.projectRoots.set(project.projectId, project.path);
      }
      const advertised = projects.map((p: any) => ({ projectId: p.projectId, label: p.label, ...(p.branch ? { branch: p.branch } : {}), hostId: p.hostId }));
      if (!advertised.some((p: any) => p.projectId === 'workspace')) advertised.unshift({ projectId: 'workspace', label: 'Bridge workspace', hostId: 'local' });
      return { projects: advertised };
    }
    if (method === 'bridge.thread.list') {
      fields(params, ['limit', 'cursor']);
      const result = await this.send('call', { method: 'thread/list', params });
      this.verifiedMethods.add('bridge.thread.list');
      const nativeThreads = Array.isArray(result?.data) ? result.data : [];
      if (this.options.threadProvider) {
        try {
          const sidebar = await this.options.threadProvider(params);
          return { threads: mergeThreadViews(nativeThreads, sidebar, this.projectRoots), nextCursor: result.nextCursor };
        } catch {
          // Fall back to native thread metadata if Desktop sidebar tools are unavailable.
        }
      }
      return { threads: mergeThreadViews(nativeThreads, {}, this.projectRoots), nextCursor: result.nextCursor };
    }
    if (method === 'bridge.thread.read') { fields(params, ['threadId']); nonempty(params.threadId, 'threadId'); const result = await this.send('call', { method: 'thread/read', params: { threadId: params.threadId, includeTurns: true } }); this.verifiedMethods.add('bridge.thread.read'); return { thread: threadView(result.thread) }; }
    if (method === 'bridge.thread.create') {
      if (!this.runtimeFeatures.allowControl) throw new BridgeError('policy.control_disabled', 'Thread creation is disabled');
      fields(params, ['projectId']);
      await this.call('bridge.project.list', {});
      const root = this.projectRoots.get(params.projectId);
      if (!root) throw new BridgeError('project.not_found', 'Select a project advertised by this Desktop');
      const native = { cwd: root, ...(params.projectId === 'workspace' ? {} : { projectId: params.projectId }) };
      validateNative('ThreadStartParams', native);
      const result = await this.send('call', { method: 'thread/start', params: native });
      this.verifiedMethods.add(method);
      return { thread: { ...threadView(result.thread), projectId: params.projectId } };
    }
    if (method === 'bridge.thread.resume') {
      if (!this.runtimeFeatures.allowControl) throw new BridgeError('policy.control_disabled', 'Thread resume is disabled');
      fields(params, ['threadId']); nonempty(params.threadId, 'threadId');
      validateNative('ThreadResumeParams', params);
      const result = await this.send('call', { method: 'thread/resume', params: { threadId: params.threadId, excludeTurns: true } });
      this.verifiedMethods.add(method);
      return { thread: threadView(result.thread), model: result.model, effort: result.reasoningEffort };
    }
    if (method.startsWith('turn/') && !this.runtimeFeatures.allowControl) throw new BridgeError('policy.control_disabled', 'Desktop control is disabled');
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
    if (!this.runtimeFeatures.allowApprovals) throw new BridgeError('policy.control_disabled', 'Desktop approval replies are disabled');
    const observed = this.serverRequests.get(id);
    if (!observed) throw new BridgeError('server_request.resolved', 'Unknown Desktop request');
    await this.send('respond', { nativeId: id, method: observed.method, result });
  }

  async close() {
    if (this.poller) clearInterval(this.poller);
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.child && !this.child.killed) {
      try { this.lastCleanup = await this.send('shutdown', {}); this.hooksRestored = this.lastCleanup?.hooksRestored === true; } catch { /* helper may already be gone */ }
      this.status = 'stopped';
      this.child.kill();
    }
    this.fail(new BridgeError('backend.disconnected', 'Desktop shared adapter closed'));
    this.status = 'stopped';
    this.hooksInstalled = false;
  }

  uiStatus() {
    return {
      kind: this.kind,
      helper: { status: this.child && !this.child.killed ? 'running' : 'stopped', pid: this.helperPid, executable: this.options.python ?? process.env.MOBILE_CODEX_FRIDA_PYTHON ?? 'python', pythonVersion: this.helperVersions.python, fridaVersion: this.helperVersions.frida },
      injection: { status: this.hooksInstalled ? 'installed' : 'not-installed', hooksInstalled: this.hooksInstalled, hooksRestored: this.hooksRestored, targetPid: this.options.pid },
      settingsUi: this.settingsUiStatus,
      renderer: this.rendererInfo,
      control: { allowControl: this.runtimeFeatures.allowControl, allowApprovals: this.runtimeFeatures.allowApprovals, startupAllowControl: this.options.allowControl === true },
      diagnostic: this.lastDiagnostic,
      lastProbeSeq: this.lastProbeSeq,
    };
  }
}
