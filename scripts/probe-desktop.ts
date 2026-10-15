import { discoverDesktop } from '../src/discovery.ts';
import { NativePipeClient } from '../src/native-pipe.ts';

const discovery = await discoverDesktop();
const output: any = { discovery, nativePipe: { configured: Boolean(process.env.CODEX_APP_TOOLS_PIPE_PATH) } };
if (process.env.CODEX_APP_TOOLS_PIPE_PATH) {
  const client = new NativePipeClient(process.env.CODEX_APP_TOOLS_PIPE_PATH, 5000);
  try {
    const result = await client.request('tools/list', { threadStartKind: 'all' });
    output.nativePipe.connected = true;
    output.nativePipe.toolCount = result.tools.length;
    output.nativePipe.tools = result.tools.map((tool: any) => ({ name: tool.name, namespace: tool.namespace }));
  } catch (error) {
    output.nativePipe.connected = false;
    output.nativePipe.error = error instanceof Error ? error.message : String(error);
  } finally { client.close(); }
}
console.log(JSON.stringify(output, null, 2));
