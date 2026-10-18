import { isAbsolute, relative, resolve, sep } from 'node:path';

// Mobile task views deliberately exclude raw command output, environment,
// filesystem metadata, credentials, and low-level tool payloads.
export function threadView(thread: any) {
  const t = thread ?? {};
  const projectId = typeof t.projectId === 'string'
    ? t.projectId
    : typeof t.project?.projectId === 'string'
      ? t.project.projectId
      : typeof t.project?.id === 'string'
        ? t.project.id
        : undefined;
  const pinned = t.pinned === true || t.isPinned === true || t.pinnedSummary === true;
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
      items: (turn.items ?? []).filter((item: any) => ['userMessage', 'agentMessage', 'plan'].includes(item.type)).map((item: any) => ({
        id: item.id,
        type: item.type,
        ...(typeof item.text === 'string' ? { text: item.text } : {}),
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

  const pinnedEntries = Array.isArray(sidebar?.pinnedThreads) ? sidebar.pinnedThreads : [];
  const pinnedIds = new Set<string>(
    pinnedEntries
      .map((entry: any) => typeof entry === 'string' ? entry : entry?.id ?? entry?.threadId)
      .filter((id: any): id is string => typeof id === 'string'),
  );
  const sidebarThreads = [
    ...(Array.isArray(sidebar?.threads) ? sidebar.threads : Array.isArray(sidebar) ? sidebar : []),
    ...(Array.isArray(sidebar?.data) ? sidebar.data : []),
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
  const direct = typeof thread?.projectId === 'string'
    ? thread.projectId
    : typeof thread?.project?.projectId === 'string'
      ? thread.project.projectId
      : typeof thread?.project?.id === 'string'
        ? thread.project.id
        : undefined;
  if (direct) {
    return direct;
  }
  if (typeof thread?.cwd !== 'string' || !isAbsolute(thread.cwd)) return undefined;

  let match: { projectId: string; length: number } | undefined;
  for (const [projectId, projectRoot] of roots) {
    const root = resolve(projectRoot);
    const pathFromRoot = relative(root, resolve(thread.cwd));
    const outside = pathFromRoot === '..' || pathFromRoot.startsWith(`..${sep}`) || isAbsolute(pathFromRoot);
    if (outside) continue;
    const length = root.length;
    if (!match || length > match.length) match = { projectId, length };
  }
  return match?.projectId;
}

export function mobileNotification(message: any): { method: string; data: any } | undefined {
  const p = message.params ?? {};
  switch (message.method) {
    case 'item/agentMessage/delta': case 'item/plan/delta':
      return { method: 'event.item.delta', data: { threadId: p.threadId, turnId: p.turnId, itemId: p.itemId, delta: p.delta } };
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
