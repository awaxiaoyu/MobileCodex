import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { NativePipeClient } from './native-pipe.ts';
import { BridgeError } from './errors.ts';
import { fields, nonempty } from './policy.ts';
import { schemaErrors } from './schema.ts';
import type { Backend, JsonObject } from './types.ts';

export function toolResult(result: any) {
  if (!result?.success) throw new BridgeError('desktop.tool_failed', 'Desktop tool failed');
  // The Desktop tool host has used both inputText and text content items.
  // Prefer structuredContent when it is present, then fall back to the
  // serialized content for older hosts.
  if (result.structuredContent !== undefined) return result.structuredContent;
  const texts = (result.contentItems ?? [])
    .filter((item: any) => ['inputText', 'text', 'outputText'].includes(item.type) && typeof item.text === 'string')
    .map((item: any) => item.text);
  const parsed = texts.map((text: string) => { try { return JSON.parse(text); } catch { return text; } });
  return parsed.length === 1 ? parsed[0] : parsed;
}

export class DesktopToolsBackend extends EventEmitter implements Backend {
  id = `desktop_tools_${randomUUID()}`;
  kind = 'desktop-tools' as const;
  generation = 1;
  status = 'stopped';
  methods = new Set<string>();
  client: NativePipeClient;
  context: { threadId: string; turnId: string; hostId: string };
  catalog = new Map<string, any>();
  verified = new Set<string>();
  verifiedMethods = new Set<string>();
  constructor(options: { pipePath: string; threadId: string; turnId: string; hostId?: string }) {
    super();
    this.client = new NativePipeClient(options.pipePath, 15_000);
    this.context = { threadId: options.threadId, turnId: options.turnId, hostId: options.hostId ?? 'local' };
  }
  async start() {
    this.status = 'connecting';
    try {
      const result = await this.client.request('tools/list', { threadStartKind: 'all' });
      for (const tool of result.tools) if (tool.namespace === 'codex_app') this.catalog.set(tool.name, tool);
      for (const [method, tool] of [['bridge.project.list', 'list_projects'], ['bridge.thread.list', 'list_threads'], ['bridge.thread.read', 'read_thread'], ['bridge.automation.read', 'automation_update']]) {
        if (this.catalog.has(tool)) this.methods.add(method);
      }
      this.status = 'connected';
    } catch (error) { this.status = 'errored'; this.client.close(); throw error; }
  }
  async invoke(name: string, args: JsonObject) {
    const tool = this.catalog.get(name);
    if (!tool) throw new BridgeError('capability.unavailable', 'Desktop tool not registered');
    const errors = schemaErrors(tool.inputSchema, args);
    if (errors.length) throw new BridgeError('protocol.invalid_params', errors.join('; '));
    const result = toolResult(await this.client.request('tools/call', {
      arguments: args, callerSource: 'codex', callId: `mobile-bridge-${randomUUID()}`,
      hostId: this.context.hostId, namespace: tool.namespace,
      threadId: this.context.threadId, tool: name, turnId: this.context.turnId,
    }));
    this.verified.add(name);
    return result;
  }
  async call(method: string, params: JsonObject) {
    if (this.status !== 'connected') throw new BridgeError('backend.disconnected', 'Desktop NativePipe is not connected');
    switch (method) {
      case 'bridge.project.list': fields(params, []); { const result = await this.invoke('list_projects', {}); this.verifiedMethods.add(method); return result; }
      case 'bridge.thread.list': fields(params, ['limit']); { const result = await this.invoke('list_threads', params); this.verifiedMethods.add(method); return result; }
      case 'bridge.thread.read':
        fields(params, ['threadId', 'cursor', 'turnLimit']); nonempty(params.threadId, 'threadId');
        return this.invoke('read_thread', { ...params, includeOutputs: false, maxOutputCharsPerItem: 0 });
      case 'bridge.automation.read':
        fields(params, ['id']); nonempty(params.id, 'id'); return this.invoke('automation_update', { mode: 'view', id: params.id });
      default: throw new BridgeError('capability.unavailable', 'Desktop NativePipe has no raw task-control endpoint; injection/shared connection has not been verified');
    }
  }
  async close() { this.client.close(); this.status = 'stopped'; }
}
