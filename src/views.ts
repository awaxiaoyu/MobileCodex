import { isAbsolute, relative, resolve, sep, win32 } from 'node:path';

// Mobile task views deliberately exclude raw command output, environment,
// filesystem metadata, credentials, and low-level tool payloads.
export function threadView(thread: any) {
  const t = thread ?? {};
  const projectId = projectIdValue(t);
  const pinned = isPinnedValue(t);
  const preview = [t.preview, t.summary, t.firstUserMessage, t.lastMessage]
    .find((value) => typeof value === 'string' && value.trim().length > 0);
  return {
    id: t.id ?? t.threadId,
    title: t.name ?? t.title ?? t.preview ?? '',
    ...(typeof preview === 'string' ? { preview: preview.trim().slice(0, 300) } : {}),
    status: t.status,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
    ...(projectId ? { projectId } : {}),
    ...(pinned ? { pinned: true } : {}),
    ...(t.turns ? { turns: t.turns.map((turn: any) => ({
      id: turn.id,
      status: turn.status,
      error: turn.error,
        items: (turn.items ?? []).filter((item: any) => ['userMessage', 'agentMessage', 'plan', 'reasoning'].includes(item.type)).map((item: any) => ({
        id: item.id,
        type: item.type,
        ...(typeof item.text === 'string' ? { text: item.text } : {}),
        ...(item.type === 'reasoning' && Array.isArray(item.summary) ? {
          text: item.summary
            .filter((part: any) => part?.type === 'summary_text' && typeof part.text === 'string')
            .map((part: any) => part.text)
            .join('\n'),
        } : {}),
        ...(Array.isArray(item.content) ? { content: item.content.filter((c: any) => c.type === 'text').map((c: any) => ({ type: 'text', text: c.text })) } : {}),
      })),
    })) } : {}),
  };
}

export function mergeThreadViews(nativeThreads: any[], sidebar: any, roots: Map<string, string>) {
  const threads = new Map<string, any>();
  for (const raw of nativeThreads) {
    const view = threadView(raw);
    if (typeof view.id !== 'string') continue;
    const projectId = projectIdForThread(raw, roots) ?? view.projectId;
    threads.set(view.id, { ...view, ...(projectId ? { projectId } : {}) });
  }

  const sidebarRoot = sidebar?.data && typeof sidebar.data === 'object' && !Array.isArray(sidebar.data)
    ? sidebar.data
    : sidebar;
  const pinnedEntries = firstArray(sidebarRoot, ['pinnedThreads', 'pinned', 'pinnedSummaries', 'pinnedChats']);
  const pinnedIds = new Set<string>(
    pinnedEntries
      .map((entry: any) => typeof entry === 'string' ? entry : entry?.id ?? entry?.threadId)
      .filter((id: any): id is string => typeof id === 'string'),
  );
  const sidebarThreads = [
    ...(Array.isArray(sidebarRoot) ? sidebarRoot : []),
    ...firstArray(sidebarRoot, ['threads', 'recent', 'recentThreads', 'chats', 'conversations']),
    ...projectThreads(sidebarRoot),
    ...pinnedEntries.filter((entry: any) => entry && typeof entry === 'object' && !Array.isArray(entry)),
  ];

  for (const raw of sidebarThreads) {
    const view = threadView(raw);
    if (typeof view.id !== 'string') continue;
    const projectId = projectIdForThread(raw, roots) ?? view.projectId;
    const merged = { ...(threads.get(view.id) ?? {}) };
    for (const [key, value] of Object.entries(view)) {
      if (value !== undefined && !(key === 'title' && value === '')) merged[key] = value;
    }
    if (projectId) merged.projectId = projectId;
    if (pinnedIds.has(view.id) || view.pinned) merged.pinned = true;
    threads.set(view.id, merged);
  }

  for (const id of pinnedIds) {
    const thread = threads.get(id);
    if (thread) thread.pinned = true;
  }
  return [...threads.values()];
}

export function projectIdForThread(thread: any, roots: Map<string, string>) {
  const direct = projectIdValue(thread);
  if (direct) {
    return direct;
  }
  if (typeof thread?.cwd !== 'string') return undefined;
  const cwd = normalizeNativePath(thread.cwd);
  const pathApi = isWindowsAbsolute(cwd) ? win32 : undefined;
  if (!(pathApi ? pathApi.isAbsolute(cwd) : isAbsolute(cwd))) return undefined;

  let match: { projectId: string; length: number } | undefined;
  for (const [projectId, projectRoot] of roots) {
    const normalizedRoot = normalizeNativePath(projectRoot);
    if (pathApi && !isWindowsAbsolute(normalizedRoot)) continue;
    const root = pathApi ? pathApi.resolve(normalizedRoot) : resolve(normalizedRoot);
    const resolvedCwd = pathApi ? pathApi.resolve(cwd) : resolve(cwd);
    const pathFromRoot = pathApi ? pathApi.relative(root, resolvedCwd) : relative(root, resolvedCwd);
    const separator = pathApi ? '\\' : sep;
    const outside = pathFromRoot === '..' || pathFromRoot.startsWith(`..${separator}`) ||
      (pathApi ? pathApi.isAbsolute(pathFromRoot) : isAbsolute(pathFromRoot));
    if (outside) continue;
    const length = root.length;
    if (!match || length > match.length) match = { projectId, length };
  }
  return match?.projectId;
}

function normalizeNativePath(value: string) {
  return value.replace(/^\\\\\?\\UNC\\/i, '\\\\').replace(/^\\\\\?\\/, '');
}

function isWindowsAbsolute(value: string) {
  return /^[a-z]:[\\/]/i.test(value) || /^\\\\/.test(value);
}

function firstArray(value: any, keys: string[]) {
  for (const key of keys) if (Array.isArray(value?.[key])) return value[key];
  return [];
}

function projectThreads(value: any): any[] {
  const groups = firstArray(value, ['projects', 'projectGroups', 'byProject']);
  const result: any[] = [];
  for (const group of groups) {
    if (Array.isArray(group)) result.push(...group);
    else if (group && typeof group === 'object') {
      const project = group.project ?? group.projectId ?? group.id;
      for (const thread of firstArray(group, ['threads', 'chats', 'conversations'])) {
        result.push(project && typeof thread === 'object' && !thread.project && !thread.projectId
          ? { ...thread, project: typeof project === 'object' ? project : { id: project } }
          : thread);
      }
    }
  }
  return result;
}

function projectIdValue(thread: any): string | undefined {
  const value = thread?.projectId ?? thread?.project?.projectId ?? thread?.project?.id ??
    thread?.project?.slug ?? thread?.project?.path ?? thread?.projectRoot ?? thread?.workspaceId;
  if (typeof value === 'string' && value.trim()) return value;
  if (typeof thread?.project === 'string' && thread.project.trim()) return thread.project;
  return undefined;
}

function isPinnedValue(thread: any): boolean {
  return thread?.pinned === true || thread?.isPinned === true || thread?.pinnedSummary === true ||
    thread?.is_pinned === true || thread?.pin === true;
}

export function mobileNotification(message: any): { method: string; data: any } | undefined {
  const p = message.params ?? {};
  switch (message.method) {
    case 'item/agentMessage/delta': case 'item/plan/delta':
    case 'item/reasoning/summaryTextDelta': case 'item/reasoning/textDelta':
      return { method: 'event.item.delta', data: { threadId: p.threadId, turnId: p.turnId, itemId: p.itemId, delta: p.delta, type: message.method.startsWith('item/reasoning/') ? 'reasoning' : message.method === 'item/plan/delta' ? 'plan' : 'agentMessage' } };
    case 'thread/started':
      return { method: 'event.thread.started', data: { thread: threadView(p.thread) } };
    case 'thread/status/changed': case 'turn/started': case 'turn/completed':
      return { method: 'event.task.status', data: { threadId: p.threadId, turnId: p.turnId ?? p.turn?.id, status: p.status ?? p.turn?.status, error: p.turn?.error } };
    case 'turn/diff/updated':
      return { method: 'event.diff.updated', data: { threadId: p.threadId, turnId: p.turnId, diff: p.diff } };
    case 'turn/plan/updated':
      return { method: 'event.plan.updated', data: { threadId: p.threadId, turnId: p.turnId, plan: p.plan, explanation: p.explanation } };
    case 'item/started': case 'item/completed':
      return { method: 'event.item.status', data: { threadId: p.threadId, turnId: p.turnId, itemId: p.item?.id, type: p.item?.type, status: message.method.endsWith('started') ? 'started' : 'completed', ...(p.item?.type === 'agentMessage' ? { text: p.item.text } : {}) } };
    case 'serverRequest/resolved':
      return { method: 'event.serverRequest.resolved', data: { threadId: p.threadId, requestId: p.requestId } };
    case 'error':
      return { method: 'event.task.error', data: { threadId: p.threadId, turnId: p.turnId, error: p.error, willRetry: p.willRetry } };
    default: return undefined;
  }
}
