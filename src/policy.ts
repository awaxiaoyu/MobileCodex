import { BridgeError } from './errors.ts';
import { validateNative } from './schema.ts';
import type { Envelope, JsonObject } from './types.ts';

export function object(value: any, label = 'payload'): JsonObject {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new BridgeError('protocol.invalid_params', `${label} must be an object`);
  return value;
}
export function fields(value: JsonObject, allowed: string[]) {
  for (const key of Object.keys(value)) if (!allowed.includes(key)) throw new BridgeError('policy.field_not_allowed', `Field is not allowed: ${key}`);
}
export function nonempty(value: any, label: string): string {
  if (typeof value !== 'string' || !value.trim()) throw new BridgeError('protocol.invalid_params', `${label} must be a nonempty string`);
  return value;
}

export function validateEnvelope(raw: any): Envelope {
  const message = object(raw, 'envelope');
  fields(message, ['v', 'kind', 'method', 'payload', 'id', 'backendId', 'backendGeneration', 'threadId', 'turnId', 'ack']);
  if (message.v !== 1 || !['request', 'server.response'].includes(message.kind)) throw new BridgeError('protocol.invalid_envelope', 'Expected a v1 request or server.response');
  nonempty(message.id, 'id');
  nonempty(message.method, 'method');
  object(message.payload);
  if (message.backendId !== undefined) {
    nonempty(message.backendId, 'backendId');
    if (!Number.isSafeInteger(message.backendGeneration) || message.backendGeneration < 1) throw new BridgeError('protocol.invalid_envelope', 'backendGeneration is required');
  } else if (message.backendGeneration !== undefined || message.threadId !== undefined || message.turnId !== undefined) {
    throw new BridgeError('protocol.invalid_envelope', 'backendId is required');
  }
  for (const key of ['threadId', 'turnId']) if (message[key] !== undefined) nonempty(message[key], key);
  if (message.ack !== undefined) {
    const ack = object(message.ack, 'ack');
    fields(ack, ['streamId', 'seq']);
    nonempty(ack.streamId, 'ack.streamId');
    if (!Number.isSafeInteger(ack.seq) || ack.seq < 0) throw new BridgeError('protocol.invalid_envelope', 'Invalid ack.seq');
  }
  return message as Envelope;
}

const rules: Record<string, { schema: string; fields: string[] }> = {
  'model/list': { schema: 'ModelListParams', fields: ['cursor', 'limit'] },
  'turn/start': { schema: 'TurnStartParams', fields: ['threadId', 'input', 'model', 'effort', 'collaborationMode'] },
  'turn/steer': { schema: 'TurnSteerParams', fields: ['threadId', 'expectedTurnId', 'input'] },
  'turn/interrupt': { schema: 'TurnInterruptParams', fields: ['threadId', 'turnId'] },
};
export const nativeAllowlist = Object.keys(rules);

export function validateNativeRequest(method: string, params: any, envelope?: Envelope) {
  const rule = Object.hasOwn(rules, method) ? rules[method] : undefined;
  if (!rule) throw new BridgeError('policy.method_not_allowed', `Native method is not allowed: ${method}`);
  params = object(params, 'params');
  fields(params, rule.fields);
  validateNative(rule.schema, params);
  if (params.collaborationMode != null) {
    const collaboration = object(params.collaborationMode, 'collaborationMode');
    fields(collaboration, ['mode', 'settings']);
    const settings = object(collaboration.settings, 'settings');
    fields(settings, ['model', 'reasoning_effort', 'developer_instructions']);
    if (settings.developer_instructions != null) throw new BridgeError('policy.field_not_allowed', 'Mobile cannot supply developer instructions');
    if (params.model && params.model !== settings.model || params.effort && settings.reasoning_effort && params.effort !== settings.reasoning_effort) throw new BridgeError('protocol.context_mismatch', 'Conflicting model or effort selection');
  }
  if (params.input !== undefined) {
    if (!params.input.length) throw new BridgeError('protocol.invalid_params', 'At least one text input is required');
    for (const input of params.input) {
      if (input.type !== 'text') throw new BridgeError('policy.input_not_supported', 'P0 accepts text input only');
      fields(object(input, 'input'), ['type', 'text']);
      nonempty(input.text, 'input.text');
    }
  }
  if (envelope?.threadId && params.threadId && envelope.threadId !== params.threadId) throw new BridgeError('protocol.context_mismatch', 'threadId mismatch');
  const turnId = params.turnId ?? params.expectedTurnId;
  if (envelope?.turnId && turnId && envelope.turnId !== turnId) throw new BridgeError('protocol.context_mismatch', 'turnId mismatch');
  return params;
}
