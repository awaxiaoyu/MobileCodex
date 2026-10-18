import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { CodexStateProvider } from '../src/codex-state.ts';

test('Codex state provider includes projects and pinned chats outside the recent limit', () => {
  const directory = mkdtempSync(join(tmpdir(), 'mobile-codex-state-'));
  const path = join(directory, 'state.sqlite');
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE projects(id TEXT, name TEXT, position INTEGER, updated_at_ms INTEGER);
    CREATE TABLE project_roots(project_id TEXT, path TEXT);
    CREATE TABLE thread_sections(id TEXT, name TEXT);
    CREATE TABLE threads(
      id TEXT, title TEXT, name TEXT, preview TEXT, first_user_message TEXT,
      cwd TEXT, project_id TEXT, is_pinned INTEGER, created_at_ms INTEGER,
      updated_at_ms INTEGER, git_branch TEXT, thread_section_id TEXT,
      archived INTEGER, recency_at_ms INTEGER
    );
    INSERT INTO projects VALUES ('p1', 'Workspace', 0, 3);
    INSERT INTO project_roots VALUES ('p1', 'C:\\work\\project');
    INSERT INTO thread_sections VALUES ('s1', 'Pinned');
    INSERT INTO threads VALUES ('recent', 'Recent', NULL, 'Request', 'Request', 'C:\\work\\project', NULL, 0, 2, 3, NULL, NULL, 0, 3);
    INSERT INTO threads VALUES ('pinned', 'Pinned task', NULL, 'Older request', 'Older request', 'C:\\work\\project', NULL, 0, 1, 1, NULL, 's1', 0, 1);
    INSERT INTO threads VALUES ('archived', 'Archived', NULL, 'Hidden', 'Hidden', 'C:\\work\\project', NULL, 1, 1, 1, NULL, 's1', 1, 1);
  `);
  db.close();

  try {
    const provider = new CodexStateProvider(path);
    assert.deepEqual(provider.projects().projects, [{ id: 'p1', name: 'Workspace', path: 'C:\\work\\project' }]);
    const threads = provider.threads({ limit: 1 }).threads;
    assert.deepEqual(threads.map((thread) => thread.id), ['pinned', 'recent']);
    assert.equal(threads.find((thread) => thread.id === 'pinned')?.pinned, true);
    assert.equal(threads.find((thread) => thread.id === 'recent')?.projectId, 'p1');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
