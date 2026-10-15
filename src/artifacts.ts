import { randomUUID } from 'node:crypto';
import { realpath, stat } from 'node:fs/promises';
import { resolve, relative, isAbsolute, basename, extname } from 'node:path';
import { BridgeError } from './errors.ts';

export type Artifact = { id: string; backendId: string; generation: number; threadId: string; name: string; size: number; path: string; contentType: string };
const mime: Record<string, string> = { '.pdf': 'application/pdf', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.txt': 'text/plain', '.md': 'text/markdown', '.csv': 'text/csv', '.json': 'application/json', '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation', '.mp3': 'audio/mpeg', '.mp4': 'video/mp4' };

/** References only come from task messages; no caller-supplied path API. */
export class ArtifactStore {
  private records = new Map<string, Artifact>();
  private workspace: string;
  constructor(workspace: string) { this.workspace = resolve(workspace); }
  async collect(backendId: string, generation: number, thread: any) {
    const root = await realpath(this.workspace);
    for (const turn of thread.turns ?? []) for (const item of turn.items ?? []) {
      if (item.type !== 'agentMessage' || typeof item.text !== 'string') continue;
      for (const match of item.text.matchAll(/!?\[[^\]]*\]\(<?([^\r\n)]+?)>?\)/g)) {
        let path = match[1].trim().replace(/:\d+$/, '');
        if (/^\/[A-Za-z]:[\\/]/.test(path)) path = path.slice(1);
        if (!isAbsolute(path) || !mime[extname(path).toLowerCase()]) continue;
        try {
          path = await realpath(path);
          const inside = relative(root, path);
          if (!inside || inside.startsWith('..') || isAbsolute(inside) || /(?:^|[\\/])(?:\.codex|\.git|\.local|\.env)(?:[\\/]|$)/i.test(inside)) continue;
          const info = await stat(path);
          if (!info.isFile() || info.size > 100 * 1024 * 1024) continue;
          if ([...this.records.values()].some((r) => r.backendId === backendId && r.generation === generation && r.threadId === thread.id && r.path === path)) continue;
          const id = randomUUID();
          this.records.set(id, { id, backendId, generation, threadId: thread.id, name: basename(path), path, size: info.size, contentType: mime[extname(path).toLowerCase()] });
        } catch { /* missing/deleted references are not downloadable resources */ }
      }
    }
    return this.list(backendId, generation, thread.id);
  }
  list(backendId: string, generation: number, threadId: string) {
    return [...this.records.values()].filter((r) => r.backendId === backendId && r.generation === generation && r.threadId === threadId).map(({ path, ...view }) => view);
  }
  async get(id: string, backendId: string, generation: number, threadId: string) {
    const record = this.records.get(id);
    if (!record || record.backendId !== backendId || record.generation !== generation || record.threadId !== threadId) throw new BridgeError('artifact.not_found', 'No artifact registered for this task');
    const path = await realpath(record.path);
    if (path !== record.path) throw new BridgeError('artifact.changed', 'Artifact path changed; reload task');
    return { ...record };
  }
}
