import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { BridgeError, errorPayload } from './errors.ts';
import { fields, object, nonempty, validateEnvelope, validateNativeRequest } from './policy.ts';
import { validateNative } from './schema.ts';
import { mobileNotification } from './views.ts';
import type { Backend, Envelope, NativeId } from './types.ts';
import { ArtifactStore } from './artifacts.ts';

const responseSchemas: Record<string, string> = {
  'item/commandExecution/requestApproval': 'CommandExecutionRequestApprovalResponse',
  'item/fileChange/requestApproval': 'FileChangeRequestApprovalResponse',
  'item/permissions/requestApproval': 'PermissionsRequestApprovalResponse',
  'item/tool/requestUserInput': 'ToolRequestUserInputResponse',
  'mcpServer/elicitation/request': 'McpServerElicitationRequestResponse',
};
const aliases: Record<string, string> = {
  'bridge.turn.start': 'turn/start', 'bridge.turn.steer': 'turn/steer',
  'bridge.turn.interrupt': 'turn/interrupt', 'bridge.model.list': 'model/list',
};
type RecordEntry = {
  id: string; method: string; backendId?: string; backendGeneration?: number;
  status: 'pending' | 'completed' | 'failed' | 'unknown';
  fingerprint: string; promise?: Promise<Envelope>; response?: Envelope;
};
type PendingServerRequest = {
  backend: Backend; generation: number; nativeId: NativeId; method: string;
  params: any; state: 'pending' | 'responding' | 'submitted' | 'resolved' | 'unknown';
};

function stable(value: any): string {
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  if (value !== null && typeof value === 'object') return '{' + Object.keys(value).sort().map((k) => JSON.stringify(k) + ':' + stable(value[k])).join(',') + '}';
  return JSON.stringify(value);
}
const keyFor = (id: string, backendId?: string, generation?: number) => JSON.stringify([backendId ?? null, generation ?? null, id]);

export class Bridge extends EventEmitter {
  readonly backends = new Map<string, Backend>();
  readonly requests = new Map<string, RecordEntry>();
  readonly serverRequests = new Map<string, PendingServerRequest>();
  readonly streams = new Map<string, { generation: number; streamId: string; seq: number; cache: Envelope[]; bytes: number }>();
  maxEventCache: number;
  maxCacheBytes: number;
  eventStreamEnabled = true;
  artifacts?: ArtifactStore;
  constructor(options: { maxEventCache?: number; maxCacheBytes?: number; workspace?: string } = {}) {
    super(); this.maxEventCache = options.maxEventCache ?? 500; this.maxCacheBytes = options.maxCacheBytes ?? 8 * 1024 * 1024;
    if (options.workspace) this.artifacts = new ArtifactStore(options.workspace);
  }
  async addBackend(backend: Backend) {
    if (this.backends.has(backend.id)) throw new BridgeError('backend.duplicate', 'Backend already registered');
    this.backends.set(backend.id, backend);
    backend.on('notification', (message) => this.publishNativeNotification(backend, message));
    backend.on('events.gap', () => { this.streams.delete(backend.id); this.publish(backend, { v: 1, kind: 'event', method: 'event.stream.reset', payload: { reason: 'adapter.events_lost' } }); });
    backend.on('serverRequest', (message) => this.publishServerRequest(backend, message));
    backend.on('serverRequest.claimed', (message) => {
      for (const [id, pending] of this.serverRequests) if (pending.backend === backend && pending.generation === backend.generation && pending.nativeId === message.requestId && pending.state !== 'resolved') {
        pending.state = message.state === 'unknown' ? 'unknown' : 'submitted';
        this.publish(backend, { v: 1, kind: 'event', method: 'event.serverRequest.claimed', payload: { requestId: id, state: pending.state } });
      }
    });
    backend.on('disconnected', () => {
      for (const pending of this.serverRequests.values()) if (pending.backend === backend && pending.state !== 'resolved') pending.state = 'unknown';
      this.emit('backend.disconnected', { backendId: backend.id, generation: backend.generation });
    });
    try { await backend.start(); }
    catch (error) { this.backends.delete(backend.id); throw error; }
    return backend;
  }
  async close() { await Promise.allSettled([...this.backends.values()].map((b) => b.close())); }
  listBackends() {
    return [...this.backends.values()].map((b) => ({ id: b.id, kind: b.kind, generation: b.generation, status: b.status, methods: [...b.methods] }));
  }
  streamStatus() {
    return [...this.streams.entries()].map(([backendId, stream]) => ({
      backendId,
      generation: stream.generation,
      streamId: stream.streamId,
      seq: stream.seq,
      cachedEvents: stream.cache.length,
      cachedBytes: stream.bytes,
      maxEvents: this.maxEventCache,
      maxBytes: this.maxCacheBytes,
    }));
  }
  setEventStreamEnabled(enabled: boolean) {
    this.eventStreamEnabled = enabled;
    if (!enabled) this.streams.clear();
    return this.eventStreamEnabled;
  }
  uiStatus() {
    return {
      bridge: { status: 'running', version: '0.2.0' },
      eventStreamEnabled: this.eventStreamEnabled,
      backends: this.listBackends().map((backend) => ({
        ...backend,
        details: this.backends.get(backend.id)?.uiStatus?.() ?? {},
      })),
      streams: this.streamStatus(),
    };
  }
  capabilities() {
    return {
      protocol: 'mobile-codex-bridge/v1', scopeVersion: '0.2.0', bridgeVersion: '0.2.0',
      capabilities: [...this.backends.values()].flatMap((b) => [...b.methods].map((name) => ({
        name, backendId: b.id, backendGeneration: b.generation,
        status: (b as any).verifiedMethods?.has(name) ? 'verified' : 'discovered',
        implemented: true, stability: b.kind === 'companion-standalone' ? 'schema' : 'private',
      }))),
    };
  }
  private backendFor(message: Envelope): Backend {
    if (!message.backendId || message.backendGeneration === undefined) throw new BridgeError('backend.required', 'This method requires backendId and backendGeneration');
    const backend = this.backends.get(message.backendId);
    if (!backend) throw new BridgeError('backend.not_found', 'Unknown backend');
    if (message.backendGeneration !== backend.generation) throw new BridgeError('backend.generation_mismatch', 'Backend generation is stale', false, { current: backend.generation });
    return backend;
  }
  private response(message: Envelope, payload: any, kind: Envelope['kind'] = 'response'): Envelope {
    return { v: 1, kind, method: message.method, id: message.id, payload,
      ...(message.backendId ? { backendId: message.backendId, backendGeneration: message.backendGeneration } : {}) };
  }
  async handle(raw: any): Promise<Envelope> {
    let message: Envelope;
    try { message = validateEnvelope(raw); }
    catch (error) {
      return { v: 1, kind: 'error', method: 'protocol.error', payload: errorPayload(error),
        ...(typeof raw?.id === 'string' ? { id: raw.id } : {}) };
    }
    try {
      if (message.kind === 'server.response') return await this.handleServerResponse(message);
      if (message.backendId) this.backendFor(message);
      if (message.method === 'bridge.request.get') {
        fields(message.payload, ['requestId']); nonempty(message.payload.requestId, 'requestId');
        const record = this.requests.get(keyFor(message.payload.requestId, message.backendId, message.backendGeneration));
        if (!record) throw new BridgeError('request.not_found', 'Unknown request in this backend generation');
        return this.response(message, { requestId: record.id, status: record.status, ...(record.response ? { response: record.response } : {}) });
      }
      const key = keyFor(message.id!, message.backendId, message.backendGeneration);
      const fingerprint = stable({ ...message, ack: undefined });
      const previous = this.requests.get(key);
      if (previous) {
        if (previous.fingerprint !== fingerprint) throw new BridgeError('request.id_conflict', 'Request id was used with different parameters');
        return await previous.promise!;
      }
      // Retain at most 1000 completed request results. No durable exactly-once
      // guarantee: changing Bridge/backend instance requires reconciliation.
      if (this.requests.size >= 1000) {
        const oldest = [...this.requests.entries()].find(([, r]) => r.status !== 'pending');
        if (oldest) this.requests.delete(oldest[0]);
        else throw new BridgeError('bridge.busy', 'Too many pending requests');
      }
      const record: RecordEntry = { id: message.id!, method: message.method, backendId: message.backendId, backendGeneration: message.backendGeneration, status: 'pending', fingerprint };
      this.requests.set(key, record);
      record.promise = this.execute(message).then((response) => {
        record.response = response;
        record.status = response.kind === 'error' ? response.payload.code === 'backend.result_unknown' ? 'unknown' : 'failed' : 'completed';
        return response;
      });
      return await record.promise;
    } catch (error) { return this.response(message, errorPayload(error), 'error'); }
  }
  private async execute(message: Envelope): Promise<Envelope> {
    try {
      const p = message.payload;
      if (message.method === 'bridge.capabilities.get') { fields(p, []); return this.response(message, this.capabilities()); }
      if (message.method === 'bridge.backends.list') { fields(p, []); return this.response(message, { backends: this.listBackends() }); }
      const backend = this.backendFor(message);
      if (message.method === 'bridge.artifact.list') {
        fields(p, ['threadId']); nonempty(p.threadId, 'threadId');
        if (!this.artifacts || !backend.methods.has('bridge.thread.read')) throw new BridgeError('capability.unavailable', 'Task artifacts are unavailable');
        const result = await backend.call('bridge.thread.read', { threadId: p.threadId });
        return this.response(message, { artifacts: await this.artifacts.collect(backend.id, backend.generation, result.thread) });
      }
      if (message.method === 'bridge.snapshot.get') {
        fields(p, ['threadId']); nonempty(p.threadId, 'threadId');
        if (!backend.methods.has('bridge.thread.read')) throw new BridgeError('capability.unavailable', 'Backend cannot snapshot threads');
        for (let attempt = 0; attempt < 3; attempt++) {
          await backend.flush?.();
          const before = this.streamFor(backend).seq;
          const state = await backend.call('bridge.thread.read', { threadId: p.threadId });
          await backend.flush?.();
          const stream = this.streamFor(backend);
          if (stream.seq !== before && stream.cache.some((e) => e.seq! > before && e.threadId === p.threadId)) continue;
          if (stream.cache[0]?.seq && stream.cache[0].seq > before + 1) continue;
          const approvals = [...this.serverRequests].filter(([, pending]) => pending.backend === backend && pending.generation === backend.generation && pending.params.threadId === p.threadId && pending.state === 'pending').map(([id, pending]) => ({ id, method: pending.method, payload: pending.params }));
          return { ...this.response(message, { ...state, approvals }, 'snapshot'), threadId: p.threadId, streamId: stream.streamId, seq: stream.seq };
        }
        throw new BridgeError('snapshot.unstable', 'Task is changing during snapshot; resume cached events and retry', true);
      }
      if (message.method === 'bridge.events.resume') {
        fields(p, ['streamId', 'afterSeq']); nonempty(p.streamId, 'streamId');
        if (!Number.isSafeInteger(p.afterSeq) || p.afterSeq < 0) throw new BridgeError('protocol.invalid_params', 'Invalid afterSeq');
        return this.response(message, this.resume(backend.id, p.afterSeq, p.streamId));
      }
      if (!backend.methods.has(message.method)) throw new BridgeError('capability.unavailable', 'Capability is not registered for this backend');
      const alias = Object.hasOwn(aliases, message.method) ? aliases[message.method] : undefined;
      let method = alias ?? message.method;
      let params = p;
      if (message.method === 'codex.request') {
        fields(p, ['method', 'params']); method = nonempty(p.method, 'payload.method'); params = p.params ?? {};
      }
      if (message.method === 'codex.request' || alias) params = validateNativeRequest(method, params, message);
      else {
        for (const name of ['threadId', 'turnId'] as const) if (message[name] !== undefined && params[name] !== undefined && message[name] !== params[name]) throw new BridgeError('protocol.context_mismatch', name + ' mismatch');
      }
      const result = await backend.call(method, params);
      if (method.startsWith('turn/') && result?.turn) return this.response(message, { turn: { id: result.turn.id, status: result.turn.status, error: result.turn.error } });
      return this.response(message, result);
    } catch (error) { return this.response(message, errorPayload(error), 'error'); }
  }
  private async handleServerResponse(message: Envelope): Promise<Envelope> {
    const backend = this.backendFor(message);
    const pending = this.serverRequests.get(message.id!);
    if (!pending || pending.state !== 'pending') throw new BridgeError('server_request.resolved', 'Request already submitted, resolved or unknown');
    if (pending.backend !== backend || pending.generation !== backend.generation || pending.method !== message.method) throw new BridgeError('protocol.context_mismatch', 'Server request backend or method mismatch');
    for (const name of ['threadId', 'turnId'] as const) if (message[name] !== undefined && pending.params[name] !== message[name]) throw new BridgeError('protocol.context_mismatch', name + ' mismatch');
    validateNative(responseSchemas[pending.method], message.payload);
    if (!backend.respond) throw new BridgeError('server_request.unavailable', 'Backend cannot accept server response');
    pending.state = 'responding';
    try { await backend.respond(pending.nativeId, message.payload); if (pending.state === 'responding') pending.state = 'submitted'; }
    catch (error) { if ((pending as PendingServerRequest).state !== 'resolved') pending.state = 'unknown'; throw error; }
    return this.response(message, { submitted: true });
  }
  private streamFor(backend: Backend) {
    let stream = this.streams.get(backend.id);
    if (!stream || stream.generation !== backend.generation) {
      stream = { generation: backend.generation, streamId: randomUUID(), seq: 0, cache: [], bytes: 0 };
      this.streams.set(backend.id, stream);
    }
    return stream;
  }
  private publish(backend: Backend, event: Envelope) {
    if (!this.eventStreamEnabled) return;
    const stream = this.streamFor(backend);
    event.backendId = backend.id; event.backendGeneration = backend.generation;
    event.streamId = stream.streamId; event.seq = ++stream.seq;
    const bytes = Buffer.byteLength(JSON.stringify(event));
    stream.cache.push(event); stream.bytes += bytes;
    while (stream.cache.length && (stream.cache.length > this.maxEventCache || stream.bytes > this.maxCacheBytes)) stream.bytes -= Buffer.byteLength(JSON.stringify(stream.cache.shift()));
    this.emit('event', event);
  }
  private publishNativeNotification(backend: Backend, message: any) {
    const mapped = mobileNotification(message);
    if (!mapped) return;
    if (message.method === 'serverRequest/resolved') {
      for (const [id, pending] of this.serverRequests) if (pending.backend === backend && pending.generation === backend.generation && pending.nativeId === message.params?.requestId) {
        pending.state = 'resolved'; mapped.data.requestId = id;
      }
    }
    this.publish(backend, { v: 1, kind: 'event', method: mapped.method, payload: mapped.data,
      ...(mapped.data.threadId ? { threadId: mapped.data.threadId } : {}),
      ...(mapped.data.turnId ? { turnId: mapped.data.turnId } : {}) });
  }
  private publishServerRequest(backend: Backend, message: any) {
    if (!Object.hasOwn(responseSchemas, message.method)) {
      this.emit('host.request.unsupported', { backendId: backend.id, method: message.method });
      (backend as any).rejectUnsupportedRequest?.(message.id);
      return;
    }
    // A renderer probe observes requests already handled by Desktop; do not
    // create a second approval owner without a verified response adapter.
    if (!backend.respond) { this.emit('host.request.pending', { backendId: backend.id, method: message.method }); return; }
    const id = 'srvreq_' + randomUUID();
    this.serverRequests.set(id, { backend, generation: backend.generation, nativeId: message.id, method: message.method, params: message.params ?? {}, state: 'pending' });
    this.publish(backend, { v: 1, kind: 'server.request', id, method: message.method, payload: message.params ?? {},
      ...(message.params?.threadId ? { threadId: message.params.threadId } : {}),
      ...(message.params?.turnId ? { turnId: message.params.turnId } : {}) });
  }
  resume(backendId: string, afterSeq: number, streamId?: string) {
    const backend = this.backends.get(backendId);
    if (!backend) throw new BridgeError('backend.not_found', 'Unknown backend');
    const stream = this.streamFor(backend);
    const first = stream.cache[0]?.seq ?? stream.seq + 1;
    if ((streamId && streamId !== stream.streamId) || afterSeq < first - 1 || afterSeq > stream.seq) throw new BridgeError('snapshot.required', 'Stream/cursor is outside the event cache; re-read task state');
    return { status: 'replaying', streamId: stream.streamId, events: stream.cache.filter((e) => e.seq! > afterSeq), throughSeq: stream.seq };
  }
}
