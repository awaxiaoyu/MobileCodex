import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import test from 'node:test';
import { mergeThreadViews, projectIdForThread, threadView } from '../src/views.ts';

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

test('thread view preserves Desktop project and pin classification', () => {
  assert.deepEqual(threadView({
    id: 't',
    title: 'Pinned task',
    project: { id: 'project-1' },
    isPinned: true,
    summary: 'A real request',
  }), {
    id: 't',
    title: 'Pinned task',
    preview: 'A real request',
    status: undefined,
    createdAt: undefined,
    updatedAt: undefined,
    projectId: 'project-1',
    pinned: true,
  });
});

test('sidebar projects and pinned threads merge with native thread history', () => {
  const project = resolve('workspace', 'MobileCodex');
  const roots = new Map([
    ['mobile-project', project],
    ['workspace', resolve('workspace')],
  ]);
  const threads = mergeThreadViews(
    [{ id: 'recent', title: 'Native title', cwd: project }],
    {
      pinnedThreads: [
        {
          id: 'pinned',
          title: 'Pinned task',
          summary: null,
          projectId: null,
          cwd: project,
          pinnedIndex: 1,
        },
      ],
      threads: [
        {
          id: 'recent',
          title: 'Recent task',
          summary: 'A real user request',
          projectId: 'mobile-project',
          cwd: project,
        },
      ],
    },
    roots,
  );

  assert.deepEqual(
    threads.map(({ id, title, preview, projectId, pinned }) => ({
      id,
      title,
      preview,
      projectId,
      pinned,
    })),
    [
      {
        id: 'recent',
        title: 'Recent task',
        preview: 'A real user request',
        projectId: 'mobile-project',
        pinned: undefined,
      },
      {
        id: 'pinned',
        title: 'Pinned task',
        preview: undefined,
        projectId: 'mobile-project',
        pinned: true,
      },
    ],
  );
});

test('sidebar nested sections preserve pinned ids and project grouping', () => {
  const threads = mergeThreadViews([], {
    data: {
      pinned: ['pinned-id'],
      projectGroups: [{
        project: { id: 'project-2' },
        conversations: [{ id: 'grouped-id', title: 'Grouped task', summary: 'Request' }],
      }],
      recentThreads: [{ id: 'pinned-id', title: 'Pinned task' }],
    },
  }, new Map());

  assert.deepEqual(threads.map(({ id, projectId, pinned }) => ({ id, projectId, pinned })), [
    { id: 'pinned-id', projectId: undefined, pinned: true },
    { id: 'grouped-id', projectId: 'project-2', pinned: undefined },
  ]);
});

test('Windows extended cwd paths still map to their project root', () => {
  const root = resolve('C:/Users/example/workspace');
  const cwd = `${root.replace(/^([A-Za-z]:)/, '\\\\?\\$1')}\\apps\\mobile`;
  assert.equal(projectIdForThread({ cwd }, new Map([['workspace', root]])), 'workspace');
});
