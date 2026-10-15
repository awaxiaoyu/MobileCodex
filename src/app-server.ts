import { EventEmitter } from 'node:events';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createInterface } from 'node:readline';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { JsonRpc } from './json-rpc.ts';
import { BridgeError } from './errors.ts';
import { fields, nonempty } from './policy.ts';
import { threadView } from './views.ts';
import type { Backend, JsonObject, NativeId } from './types.ts';

export class AppServerBackend extends EventEmitter implements Backend {
  id = `standalone_${randomUUID()}`;
  kind = 'companion-standalone' as const;
  generation = 1;
  status = 'stopped';
  methods = new Set(['bridge.project.list', 'bridge.thread.list', 'bridge.thread.read', 'bridge.thread.create', 'bridge.model.list', 'codex.request', 'bridge.turn.start', 'bridge.turn.steer', 'bridge.turn.interrupt']);
  command: string;
  args: string[];
  workspace: string;
  child?: ChildProcessWithoutNullStreams;
  rpc?: JsonRpc;
  ownedThreads = new Set<string>();
  lastServerInfo: any;
  verifiedMethods = new Set<string>();
  startedOnce = false;
  constructor(options: { command: string; args?: string[]; workspace: string }) {
    super();
    this.command = options.command;
    this.args = options.args ?? ['app-server'];
    this.workspace = resolve(options.workspace);
  }
  async start() {
    if (this.status !== 'stopped') throw new BridgeError('backend.already_started', 'Backend already started');
    if (this.startedOnce) { this.generation++; this.ownedThreads.clear(); }
    this.startedOnce = true;
    this.status = 'connecting';
    const child = spawn(this.command, this.args, { cwd: this.workspace, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child = child;
    const rpc = new JsonRpc((message) => {
      if (!child.stdin.writable) throw new BridgeError('backend.disconnected', 'app-server stdin is closed');
      child.stdin.write(`${JSON.stringify(message)}\n`);
    });
    this.rpc = rpc;
    createInterface({ input: child.stdout }).on('line', (line) => {
      try { rpc.receive(JSON.parse(line)); }
      catch { rpc.close(new BridgeError('backend.invalid_message', 'app-server returned invalid JSON')); child.kill(); }
    });
    // Drain stderr but do not copy Codex logs/content into protocol or audit logs.
    child.stderr.on('data', () => {});
    child.stdin.on('error', () => rpc.close());
    child.on('error', () => { this.status = 'errored'; rpc.close(new BridgeError('backend.start_failed', 'Could not start Codex app-server')); });
    child.on('exit', () => { this.status = 'disconnected'; rpc.close(); this.emit('disconnected'); });
    rpc.on('notification', (message) => this.emit('notification', message));
    rpc.on('serverRequest', (message) => this.emit('serverRequest', message));
    try {
      this.lastServerInfo = await rpc.request('initialize', { clientInfo: { name: 'mobile_codex_bridge', version: '0.1.0' } });
      rpc.notify('initialized');
      this.status = 'connected';
    } catch (error) { await this.close(); throw error; }
  }
  async call(method: string, params: JsonObject) {
    if (this.status !== 'connected') throw new BridgeError('backend.disconnected', 'Backend is not connected');
    if (method === 'bridge.project.list') { fields(params, []); return { projects: [{ id: 'workspace', name: this.workspace.split(/[\\/]/).at(-1), source: 'configured-workspace' }] }; }
    if (method === 'bridge.thread.create') {
      fields(params, ['projectId']);
      if (params.projectId !== 'workspace') throw new BridgeError('project.not_found', 'Select the configured workspace project');
      const result = await this.rpc!.request('thread/start', { cwd: this.workspace });
      this.ownedThreads.add(result.thread.id);
      this.verifiedMethods.add(method);
      return { thread: threadView(result.thread) };
    }
    if (method === 'bridge.thread.list') {
      fields(params, ['limit', 'cursor']);
      if (params.limit !== undefined && (!Number.isSafeInteger(params.limit) || params.limit < 1 || params.limit > 50)) throw new BridgeError('protocol.invalid_params', 'limit must be 1..50');
      if (params.cursor !== undefined) nonempty(params.cursor, 'cursor');
      const result = await this.rpc!.request('thread/list', { ...params, cwd: this.workspace, limit: params.limit ?? 20 });
      return { threads: result.data.map((thread: any) => ({ ...threadView(thread), projectId: 'workspace' })), nextCursor: result.nextCursor };
    }
    if (method === 'bridge.thread.read') {
      fields(params, ['threadId']);
      nonempty(params.threadId, 'threadId');
      const result = await this.rpc!.request('thread/read', { threadId: params.threadId, includeTurns: true });
      const actualCwd = typeof result.thread?.cwd === 'string' ? resolve(result.thread.cwd) : undefined;
      const matchesWorkspace = actualCwd && (process.platform === 'win32' ? actualCwd.toLowerCase() === this.workspace.toLowerCase() : actualCwd === this.workspace);
      if (!matchesWorkspace) throw new BridgeError('policy.thread_outside_workspace', 'Thread belongs to another workspace');
      // Reading history never promotes a Desktop thread into a standalone-owned
      // live session. P0 mutations require a thread created by this instance.
      return { thread: threadView(result.thread), liveControl: this.ownedThreads.has(params.threadId) };
    }
    if (method === 'bridge.model.list' || method === 'model/list') { const result = await this.rpc!.request('model/list', params); this.verifiedMethods.add('bridge.model.list'); return result; }
    if (method.startsWith('turn/')) {
      if (!this.ownedThreads.has(params.threadId)) throw new BridgeError('backend.thread_not_owned', 'This standalone backend can only control threads it created; Desktop history is read-only');
      return this.rpc!.request(method, params);
    }
    throw new BridgeError('capability.unavailable', `Unsupported backend method: ${method}`);
  }
  respond(id: NativeId, result: unknown) { this.rpc!.respond(id, result); }
  rejectUnsupportedRequest(id: NativeId) { this.rpc?.send({ id, error: { code: -32601, message: 'P0 standalone client has no handler for this host-internal request' } }); }
  async close() {
    this.rpc?.close();
    const child = this.child;
    if (child && child.exitCode === null) {
      child.stdin.end();
      await new Promise<void>((resolve) => {
        const timer = setTimeout(() => { child.kill(); resolve(); }, 1000);
        child.once('exit', () => { clearTimeout(timer); resolve(); });
      });
    }
    this.status = 'stopped';
  }
}
