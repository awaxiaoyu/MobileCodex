import type { EventEmitter } from 'node:events';

export type JsonObject = Record<string, any>;
export type NativeId = number | string;
export type BackendKind = 'desktop-tools' | 'desktop-shared' | 'companion-standalone';
export type Envelope = {
  v: 1;
  kind: 'request' | 'response' | 'event' | 'server.request' | 'server.response' | 'snapshot' | 'error';
  method: string;
  payload: any;
  id?: string;
  backendId?: string;
  backendGeneration?: number;
  threadId?: string;
  turnId?: string;
  streamId?: string;
  seq?: number;
  ack?: { streamId: string; seq: number };
};

export interface Backend extends EventEmitter {
  id: string;
  kind: BackendKind;
  generation: number;
  status: string;
  methods: Set<string>;
  start(): Promise<void>;
  call(method: string, params: JsonObject): Promise<any>;
  respond?(id: NativeId, result: unknown): void | Promise<void>;
  flush?(): Promise<void>;
  close(): Promise<void>;
  /** A redacted, local-only status view for the Desktop settings panel. */
  uiStatus?(): Record<string, any>;
}
