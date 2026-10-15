import { DesktopToolsBackend } from '../src/desktop-tools.ts';

const pipePath = process.env.CODEX_APP_TOOLS_PIPE_PATH;
const threadId = process.env.CODEX_THREAD_ID;
if (!pipePath || !threadId) throw new Error('Run inside the Codex task environment, or supply authorized NativePipe path and caller thread context');
const backend = new DesktopToolsBackend({ pipePath, threadId, turnId: process.env.MOBILE_CODEX_TURN_ID ?? 'bridge-readonly-probe', hostId: process.env.CODEX_APP_TOOLS_CALLER_HOST_ID });
const count = (value: any): number | undefined => {
  if (Array.isArray(value)) return value.length;
  if (value && typeof value === 'object') for (const key of ['projects', 'threads']) if (Array.isArray(value[key])) return value[key].length;
  return undefined;
};
try {
  await backend.start();
  const projects = await backend.call('bridge.project.list', {});
  const chats = await backend.call('bridge.thread.list', { limit: 1 });
  const current = await backend.call('bridge.thread.read', { threadId, turnLimit: 1 });
  console.log(JSON.stringify({ kind: backend.kind, connected: true, catalogCount: backend.catalog.size, projectCall: 'passed', projectCount: count(projects), chatListCall: 'passed', chatCount: count(chats), currentChatReadCall: current ? 'passed' : 'empty', sharedTurnControl: false }, null, 2));
} finally { await backend.close(); }
