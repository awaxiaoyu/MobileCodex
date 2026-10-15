import test from 'node:test';
import assert from 'node:assert/strict';
import { FrameDecoder, encodeFrame } from '../src/native-pipe.ts';

test('NativePipe frames decode partial and multiple writes', () => {
  const decoder = new FrameDecoder();
  const bytes = Buffer.concat([encodeFrame({ id: 1, result: { ok: true } }), encodeFrame({ id: 2, result: 'done' })]);
  assert.deepEqual(decoder.push(bytes.subarray(0, 3)), []);
  assert.deepEqual(decoder.push(bytes.subarray(3)), [{ id: 1, result: { ok: true } }, { id: 2, result: 'done' }]);
});
