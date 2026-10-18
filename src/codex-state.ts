import { DatabaseSync } from 'node:sqlite';
import { homedir } from 'node:os';
import { accessSync, constants } from 'node:fs';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { relative, resolve } from 'node:path';

/** Read-only fallback for Desktop sidebar metadata when NativePipe is absent. */
export class CodexStateProvider {
  readonly path: string;
  constructor(path = process.env.MOBILE_CODEX_STATE_DB) {
    if (path) {
      this.path = path;
    } else {
      const directory = join(homedir(), '.codex');
      let candidates: string[] = [];
      try {
        candidates = readdirSync(directory, { withFileTypes: true })
          .filter((entry) => entry.isFile() && /^state_\d+\.sqlite$/.test(entry.name))
          .map((entry) => entry.name)
          .sort((a, b) => Number(b.match(/\d+/)?.[0]) - Number(a.match(/\d+/)?.[0]));
      } catch { /* use the conventional path and report an empty view if absent */ }
      this.path = join(directory, candidates[0] ?? 'state_5.sqlite');
    }
  }

  private open() {
    accessSync(this.path, constants.R_OK);
    return new DatabaseSync(this.path, { readOnly: true });
  }

  projects() {
    let db: DatabaseSync | undefined;
    try {
      db = this.open();
      const roots = new Map<string, string>();
      for (const row of db.prepare('SELECT project_id, path FROM project_roots').all() as any[]) {
        if (typeof row.project_id === 'string' && typeof row.path === 'string') roots.set(row.project_id, row.path);
      }
      const projects = (db.prepare('SELECT id, name FROM projects ORDER BY position ASC, updated_at_ms DESC').all() as any[])
        .map((row) => ({ id: row.id, name: row.name, path: roots.get(row.id) }))
        .filter((row) => typeof row.id === 'string' && typeof row.name === 'string');
      return { projects };
    } catch {
      return { projects: [] };
    } finally {
      db?.close();
    }
  }

  threads(params: { limit?: number } = {}) {
    let db: DatabaseSync | undefined;
    try {
      db = this.open();
      const limit = Math.max(1, Math.min(100, Number.isSafeInteger(params.limit) ? params.limit! : 50));
      const rows = db.prepare(`
        SELECT t.id, t.title, t.name, t.preview, t.first_user_message, t.cwd, t.project_id,
               t.is_pinned, t.created_at_ms, t.updated_at_ms, t.git_branch,
               s.name AS section_name
        FROM threads t LEFT JOIN thread_sections s ON s.id = t.thread_section_id
        WHERE t.archived = 0 AND (
          t.is_pinned = 1 OR lower(s.name) = 'pinned' OR t.id IN (
            SELECT id FROM threads WHERE archived = 0
            ORDER BY recency_at_ms DESC, updated_at_ms DESC, id DESC LIMIT ?
          )
        )
        ORDER BY lower(s.name) = 'pinned' DESC, t.recency_at_ms DESC, t.updated_at_ms DESC, t.id DESC
      `).all(limit) as any[];
      const roots = new Map<string, string>();
      for (const row of db.prepare('SELECT project_id, path FROM project_roots').all() as any[]) {
        if (typeof row.project_id === 'string' && typeof row.path === 'string') roots.set(row.project_id, row.path);
      }
      return {
        threads: rows.filter((row) => typeof row.id === 'string').map((row) => ({
          id: row.id,
          title: row.name || row.title || row.preview || '',
          ...(typeof row.preview === 'string' && row.preview.trim() ? { preview: row.preview.trim() } : {}),
          ...(typeof row.first_user_message === 'string' && row.first_user_message.trim() ? { firstUserMessage: row.first_user_message.trim() } : {}),
          ...(typeof row.cwd === 'string' ? { cwd: row.cwd } : {}),
          ...((typeof row.project_id === 'string' ? row.project_id : inferProjectId(row.cwd, roots)) ? { projectId: row.project_id ?? inferProjectId(row.cwd, roots) } : {}),
          ...(row.is_pinned === 1 || String(row.section_name ?? '').toLowerCase() === 'pinned' ? { pinned: true } : {}),
          ...(typeof row.created_at_ms === 'number' ? { createdAt: row.created_at_ms } : {}),
          ...(typeof row.updated_at_ms === 'number' ? { updatedAt: row.updated_at_ms } : {}),
          ...(typeof row.git_branch === 'string' ? { branch: row.git_branch } : {}),
        })),
      };
    } catch {
      return { threads: [] };
    } finally {
      db?.close();
    }
  }
}

function inferProjectId(cwd: unknown, roots: Map<string, string>) {
  if (typeof cwd !== 'string' || !cwd) return undefined;
  const normalize = (value: string) => value.replace(/^\\\\\?\\UNC\\/i, '\\\\').replace(/^\\\\\?\\/, '');
  const target = resolve(normalize(cwd));
  let match: { id: string; length: number } | undefined;
  for (const [id, rootValue] of roots) {
    const root = resolve(normalize(rootValue));
    const rest = relative(root, target);
    if (rest === '..' || rest.startsWith('..\\') || rest.startsWith('../') || /^[A-Za-z]:/.test(rest)) continue;
    if (!match || root.length > match.length) match = { id, length: root.length };
  }
  return match?.id;
}
