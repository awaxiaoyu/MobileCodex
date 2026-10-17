import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { BridgeError } from './errors.ts';

// Covers the Draft-07 constructs used by the checked-in Codex request/response
// schemas. It is not a general purpose JSON Schema implementation.
export function schemaErrors(schema: any, value: any, root = schema, path = '$'): string[] {
  if (schema === true) return [];
  if (schema === false) return [`${path}: value is forbidden`];
  if (schema.$ref) {
    const keys = schema.$ref.replace(/^#\//, '').split('/');
    let target = root;
    for (const key of keys) target = target?.[key.replaceAll('~1', '/').replaceAll('~0', '~')];
    if (!target) throw new Error(`Unsupported schema reference: ${schema.$ref}`);
    return schemaErrors(target, value, root, path);
  }
  const errors: string[] = [];
  if (Object.hasOwn(schema, 'const') && JSON.stringify(schema.const) !== JSON.stringify(value)) errors.push(`${path}: invalid const`);
  if (schema.allOf) for (const part of schema.allOf) errors.push(...schemaErrors(part, value, root, path));
  if (schema.anyOf && !schema.anyOf.some((s: any) => schemaErrors(s, value, root, path).length === 0)) errors.push(`${path}: does not match anyOf`);
  if (schema.oneOf && schema.oneOf.filter((s: any) => schemaErrors(s, value, root, path).length === 0).length !== 1) errors.push(`${path}: does not match exactly one schema`);
  if (schema.enum && !schema.enum.some((v: any) => JSON.stringify(v) === JSON.stringify(value))) errors.push(`${path}: invalid enum`);
  const types = schema.type ? [schema.type].flat() : [];
  const matches = (type: string) => {
    if (type === 'null') return value === null;
    if (type === 'array') return Array.isArray(value);
    if (type === 'object') return value !== null && typeof value === 'object' && !Array.isArray(value);
    if (type === 'integer') return Number.isSafeInteger(value);
    if (type === 'number') return typeof value === 'number' && Number.isFinite(value);
    return typeof value === type;
  };
  if (types.length && !types.some(matches)) return [...errors, `${path}: expected ${types.join('/')}`];
  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(`${path}: below minimum`);
    if (schema.maximum !== undefined && value > schema.maximum) errors.push(`${path}: above maximum`);
    if (schema.format === 'uint32' && value > 0xffffffff) errors.push(`${path}: exceeds uint32`);
  }
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength) errors.push(`${path}: too short`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errors.push(`${path}: invalid pattern`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) errors.push(`${path}: too few items`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems) errors.push(`${path}: too many items`);
    if (schema.items) value.forEach((v, i) => errors.push(...schemaErrors(schema.items, v, root, `${path}[${i}]`)));
  } else if (value !== null && typeof value === 'object') {
    for (const key of schema.required ?? []) if (!Object.hasOwn(value, key)) errors.push(`${path}.${key}: required`);
    for (const [key, item] of Object.entries(value)) {
      if (schema.properties?.[key]) errors.push(...schemaErrors(schema.properties[key], item, root, `${path}.${key}`));
      else if (schema.additionalProperties === false) errors.push(`${path}.${key}: unknown field`);
      else if (schema.additionalProperties && typeof schema.additionalProperties === 'object') errors.push(...schemaErrors(schema.additionalProperties, item, root, `${path}.${key}`));
    }
  }
  return errors;
}

const cache = new Map<string, any>();
export function validateNative(name: string, value: unknown) {
  let schema = cache.get(name);
  if (!schema) {
    const appRoot = process.env.MOBILE_CODEX_APP_ROOT;
    const schemaPath = appRoot ? resolve(appRoot, 'schemas', 'codex', `${name}.json`) : new URL(`../schemas/codex/${name}.json`, import.meta.url);
    schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
    cache.set(name, schema);
  }
  const errors = schemaErrors(schema, value);
  if (errors.length) throw new BridgeError('protocol.invalid_params', errors.slice(0, 4).join('; '));
}
