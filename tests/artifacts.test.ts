import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ArtifactStore } from '../src/artifacts.ts';

test('artifacts are limited to agent-linked files in workspace and exact task context', async () => {
  const root = await mkdtemp(join(tmpdir(), 'mobile-artifact-'));
  try {
    const path = join(root, 'report.pdf'); await writeFile(path, '%PDF');
    const store = new ArtifactStore(root);
    const items = await store.collect('b', 1, { id: 't', turns: [{ items: [{ type: 'agentMessage', text: `[report](${path}) [outside](C:/Windows/win.ini)` }] }] });
    assert.equal(items.length, 1); assert.equal('path' in items[0], false);
    assert.equal((await store.get(items[0].id, 'b', 1, 't')).path, path);
    await assert.rejects(store.get(items[0].id, 'b', 1, 'other'), (e: any) => e.code === 'artifact.not_found');
    await assert.rejects(store.get(path, 'b', 1, 't'), (e: any) => e.code === 'artifact.not_found');
  } finally { await rm(root, { recursive: true, force: true }); }
});
