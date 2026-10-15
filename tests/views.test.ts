import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import test from 'node:test';
import { projectIdForThread, threadView } from '../src/views.ts';

test('thread project is inferred from the most specific root without exposing cwd', () => {
  const workspace = resolve('workspace');
  const project = resolve('workspace', 'mobile');
  const roots = new Map([
    ['workspace', workspace],
    ['mobile-project', project],
  ]);

  assert.equal(
    projectIdForThread({ cwd: resolve(project, 'apps', 'mobile') }, roots),
    'mobile-project',
  );
  assert.equal(
    projectIdForThread({ cwd: resolve(workspace, 'scripts') }, roots),
    'workspace',
  );
  assert.equal(projectIdForThread({ cwd: resolve('outside') }, roots), undefined);
  assert.deepEqual(threadView({ id: 't', cwd: project }), {
    id: 't',
    title: '',
    status: undefined,
    createdAt: undefined,
    updatedAt: undefined,
  });
});
