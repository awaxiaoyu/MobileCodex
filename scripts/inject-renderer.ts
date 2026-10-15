import { installRendererProbe } from '../adapters/renderer/probe.js';
import { CdpConnection, listLocalTargets } from '../src/cdp.ts';

const args = process.argv.slice(2);
const option = (name: string) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
const candidates = await listLocalTargets(option('--cdp') ?? 'http://127.0.0.1:9222');
const targetId = option('--target');
if (!targetId) {
  console.log(JSON.stringify({ candidates: candidates.map((t) => ({ id: t.id, title: t.title, url: t.url })), instruction: 'Select the Codex app renderer and pass --target; nothing has been injected' }, null, 2));
  process.exit(0);
}
const target = candidates.find((t) => t.id === targetId);
if (!target) throw new Error('Target is not a listed page');
const connection = await CdpConnection.connect(target);
try {
  const expression = args.includes('--dispose')
    ? 'window.__mobileCodexProbe?.dispose() ?? {disposed:false}'
    : `(${installRendererProbe.toString()})(window, ${JSON.stringify({ allowControl: args.includes('--allow-control'), hostId: option('--host') ?? 'local' })})`;
  const result = await connection.evaluate(expression);
  console.log(JSON.stringify({ targetId, result, liveTaskControlVerified: false }, null, 2));
} finally { connection.close(); }
