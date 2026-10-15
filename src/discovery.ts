import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access, readdir } from 'node:fs/promises';
import { join } from 'node:path';

const execute = promisify(execFile);
export async function discoverDesktop() {
  if (process.platform !== 'win32') return { platform: process.platform, processes: [], toolsPipePresent: Boolean(process.env.CODEX_APP_TOOLS_PIPE_PATH) };
  // Only executable identity and parent PID. Never dump process command lines,
  // config.toml, tokens, or environment values into discovery output.
  const script = `Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'codex.exe' -or ($_.Name -eq 'ChatGPT.exe' -and $_.ExecutablePath -match 'OpenAI.Codex') } | Select-Object Name,ProcessId,ParentProcessId,ExecutablePath | ConvertTo-Json -Compress`;
  const { stdout } = await execute('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true, timeout: 10_000 });
  const processes = stdout.trim() ? [JSON.parse(stdout)].flat() : [];
  const desktop = processes.filter((p: any) => p.Name === 'ChatGPT.exe' && !processes.some((parent: any) => parent.ProcessId === p.ParentProcessId && parent.Name === 'ChatGPT.exe'));
  const appServers = processes.filter((p: any) => p.Name === 'codex.exe' && desktop.some((d: any) => d.ProcessId === p.ParentProcessId));
  return { platform: 'win32', desktop, appServers, toolsPipePresent: Boolean(process.env.CODEX_APP_TOOLS_PIPE_PATH), sharedConnectionVerified: false, sharedAdapterAvailable: 'frida-experimental' };
}

export async function findCodexExecutable(explicit = process.env.MOBILE_CODEX_CLI_PATH): Promise<string> {
  if (explicit) { await access(explicit); return explicit; }
  const found = await discoverDesktop();
  const running = (found as any).appServers?.find((p: any) => p.ExecutablePath)?.ExecutablePath;
  if (running) return running;
  const local = process.env.LOCALAPPDATA;
  if (!local) throw new Error('Set MOBILE_CODEX_CLI_PATH to the Codex executable');
  const base = join(local, 'OpenAI', 'Codex', 'bin');
  const directories = await readdir(base, { withFileTypes: true });
  for (const directory of directories.filter((d) => d.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
    const candidate = join(base, directory.name, 'codex.exe');
    try { await access(candidate); return candidate; } catch { /* try the next installed version */ }
  }
  throw new Error('No Codex executable found; set MOBILE_CODEX_CLI_PATH');
}
