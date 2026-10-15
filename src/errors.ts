export class BridgeError extends Error {
  code: string;
  retryable: boolean;
  data: unknown;
  constructor(code: string, message: string, retryable = false, data?: unknown) {
    super(message);
    this.name = 'BridgeError';
    this.code = code;
    this.retryable = retryable;
    this.data = data;
  }
}

export function errorPayload(error: unknown) {
  const known = error instanceof BridgeError;
  return {
    code: known ? error.code : 'bridge.internal_error',
    message: error instanceof Error ? error.message : 'Unknown error',
    retryable: known ? error.retryable : false,
    ...(known && error.data !== undefined ? { data: error.data } : {}),
  };
}
