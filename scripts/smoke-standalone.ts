import { AppServerBackend } from '../src/app-server.ts';
import { findCodexExecutable } from '../src/discovery.ts';

const workspace = process.env.MOBILE_CODEX_WORKSPACE ?? process.cwd();
const command = await findCodexExecutable(process.env.MOBILE_CODEX_CLI_PATH);
const backend = new AppServerBackend({ command, workspace });
try {
  await backend.start();
  const models = await backend.call('model/list', {});
  console.log(JSON.stringify({ status: backend.status, kind: backend.kind, handshake: 'initialize/initialized', modelCount: Array.isArray(models?.data) ? models.data.length : undefined, modelRequestVerified: true, sharedDesktopConnectionVerified: false, modelTurnStarted: false }, null, 2));
} finally { await backend.close(); }
