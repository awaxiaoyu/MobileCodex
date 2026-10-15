"""Persistent local Frida transport for the MobileCodex Desktop adapter.

The process exposes a small JSONL command channel. It never evaluates caller
provided JavaScript: commands are registered operations (install, call, drain,
status, dispose, shutdown) and the injected agent only invokes the checked-in
renderer probe. The Frida package is deliberately external to this repository.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

sys.stdin.reconfigure(encoding='utf-8')
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')


def emit(value: dict) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)


def find_pid() -> int:
    script = "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'ChatGPT.exe' } | Select-Object -First 1 -ExpandProperty ProcessId"
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script], capture_output=True, text=True, timeout=10)
    value = result.stdout.strip()
    if not value.isdigit():
        raise RuntimeError("No ChatGPT.exe Desktop process was found")
    return int(value)


parser = argparse.ArgumentParser()
parser.add_argument("--workspace", type=Path, required=True)
parser.add_argument("--pid", type=int)
args = parser.parse_args()
compatibility = json.loads((args.workspace / 'adapters' / 'main' / 'compatibility.json').read_text(encoding='utf-8'))

deps = os.environ.get("MOBILE_CODEX_FRIDA_DEPS")
if deps:
    sys.path.insert(0, deps)
try:
    import frida  # type: ignore
except ImportError as error:
    raise SystemExit("Frida is not installed; set MOBILE_CODEX_FRIDA_DEPS to its dependency directory") from error

pid = args.pid or find_pid()
probe_source = (args.workspace / "adapters" / "renderer" / "probe.js").read_text(encoding="utf-8")
probe_source = probe_source.replace("export function installRendererProbe", "function installRendererProbe")
arbitration_source = (args.workspace / 'adapters' / 'main' / 'arbitration.js').read_text(encoding='utf-8').replace('export function installApprovalArbitration', 'function installApprovalArbitration')
state_key = "__mobileCodexBridge_" + os.urandom(12).hex()

renderer = r"""(async () => {
PROBE_SOURCE
const electronBridge = window.electronBridge;
const output = { userAgent: electronBridge?.getDesktopUserAgent?.(), shellUrl: location.href };
try {
  output.install = installRendererProbe(window, INSTALL_OPTIONS);
} catch (error) { output.error = String(error?.message ?? error); }
return output;
})()""".replace("PROBE_SOURCE", probe_source)

bootstrap = r"""(() => {
  ARBITRATION_SOURCE
  const compatibility = COMPATIBILITY;
  if (process.platform !== compatibility.platform || process.arch !== compatibility.arch || ['node', 'electron', 'chrome', 'v8'].some((key) => process.versions[key] !== compatibility[key])) throw new Error('Unsupported Desktop Main runtime');
  if (globalThis.__mobileCodexMainBridge) throw new Error('A Desktop shared adapter is already attached');
  const electron = process.mainModule.require('electron');
  const win = electron.webContents.getAllWebContents().find((item) => item.getType() === 'window' && item.getURL().startsWith('app:'));
  if (!win) throw new Error('No Codex shell renderer');
  const handlers = electron.ipcMain._invokeHandlers;
  const channel = 'codex_desktop:message-from-view';
  const originalHandler = handlers.get(channel);
  if (typeof originalHandler !== 'function') throw new Error('Missing Desktop IPC handler');
  const originalSend = win.send;
  const sendDescriptor = Object.getOwnPropertyDescriptor(win, 'send');
  const state = { phase: 'ready', outbox: [], hookEvents: [], queue: [], busy: false, disposed: false, heartbeat: Date.now() };
  const observedRequests = new Map();
  const requestKey = (id) => JSON.stringify(['local', id]);
  const push = (value) => state.outbox.push(value);
  const restore = () => {
    arbitration.restore();
    if (handlers.get(channel) === wrappedHandler) handlers.set(channel, originalHandler);
    if (win.send === wrappedSend) {
      if (sendDescriptor) Object.defineProperty(win, 'send', sendDescriptor); else delete win.send;
    }
    state.restored = handlers.get(channel) === originalHandler && win.send === originalSend;
    clearInterval(watchdog);
    if (globalThis.__mobileCodexMainBridge === state) delete globalThis.__mobileCodexMainBridge;
  };
  function metadata(direction, data) {
    if (!data || typeof data !== 'object') return;
    if (direction === 'main-to-renderer' && data.type === 'mcp-request' && data.hostId === 'local' && data.request) {
      observedRequests.set(requestKey(data.request.id), { method: data.request.method, params: data.request.params });
      if (observedRequests.size > 1000) observedRequests.delete(observedRequests.keys().next().value);
    }
    if (data.type === 'mcp-request' || data.type === 'mcp-response') state.hookEvents.push({
      kind: 'main.hook', direction, type: data.type,
      requestId: data.request?.id ?? data.response?.id,
      method: data.request?.method,
      hasResult: Object.hasOwn(data.response ?? {}, 'result'),
      threadId: data.request?.params?.threadId,
      turnId: data.request?.params?.turnId,
    });
    if (state.hookEvents.length > 500) state.hookEvents.shift();
  }
  function wrappedHandler(...values) { metadata('renderer-to-main', values[1]); return Reflect.apply(originalHandler, this, values); }
  function wrappedSend(...values) { metadata('main-to-renderer', values[1]); return Reflect.apply(originalSend, this, values); }
  handlers.set(channel, wrappedHandler);
  const arbitration = installApprovalArbitration(handlers, channel, observedRequests, (event) => state.hookEvents.push({ kind: 'approval.claimed', ...event }));
  Object.defineProperty(win, 'send', { value: wrappedSend, writable: true, configurable: true });
  const watchdog = setInterval(() => {
    if (Date.now() - state.heartbeat > 10000) {
      restore(); state.disposed = true;
      win.executeJavaScript('window.__mobileCodexProbe?.dispose()').catch(() => {});
      delete globalThis[STATE_KEY];
    }
  }, 1000);
  watchdog.unref();
  async function run(command) {
    if (state.disposed) throw new Error('Desktop adapter is disposed');
    if (!command || typeof command !== 'object' || typeof command.id !== 'string') throw new Error('Invalid bridge command');
    if (command.op === 'install') return await win.executeJavaScript(RENDERER.replace('INSTALL_OPTIONS', JSON.stringify({allowControl: command.allowControl === true, allowApprovals: command.allowApprovals === true, hostId: command.hostId ?? 'local'})));
    if (command.op === 'call') {
      if (!['model/list', 'thread/list', 'thread/read', 'thread/start', 'thread/resume', 'turn/start', 'turn/steer', 'turn/interrupt'].includes(command.method)) throw new Error('Method is not registered');
      return await win.executeJavaScript(`window.__mobileCodexProbe.call(${JSON.stringify(command.method)}, ${JSON.stringify(command.params ?? {})})`);
    }
    if (command.op === 'drain') {
      const events = await win.executeJavaScript('window.__mobileCodexProbe?.drain() ?? []');
      for (const event of events) if (event.kind === 'server.request') observedRequests.set(requestKey(event.id), { method: event.method, params: event.params });
      return { events, hooks: state.hookEvents.splice(0) };
    }
    if (command.op === 'respond') {
      const observed = observedRequests.get(requestKey(command.nativeId));
      if (!observed || observed.method !== command.method) throw new Error('Unknown server request');
      if (arbitration.hasClaimed('local', command.nativeId)) throw new Error('Server request was already answered on Desktop');
      return await win.executeJavaScript(`window.__mobileCodexProbe.respond(${JSON.stringify(command.nativeId)}, ${JSON.stringify(command.method)}, ${JSON.stringify(command.result)}, ${JSON.stringify(observed.params?.threadId ?? null)})`);
    }
    if (command.op === 'status') return await win.executeJavaScript('window.__mobileCodexProbe?.status() ?? { stopped: true }');
    if (command.op === 'dispose') {
      try { await win.executeJavaScript('window.__mobileCodexProbe?.dispose()'); } finally { restore(); state.disposed = true; }
      return { disposed: true, hooksRestored: state.restored === true };
    }
    if (command.op === 'shutdown') {
      try { await win.executeJavaScript('window.__mobileCodexProbe?.dispose()'); } finally { restore(); state.disposed = true; state.phase = 'stopped'; }
      return { stopped: true, hooksRestored: state.restored === true };
    }
    throw new Error('Unsupported bridge operation');
  }
  async function pump() {
    if (state.busy || state.disposed) return;
    const command = state.queue.shift();
    if (!command) return;
    state.busy = true;
    try { push({ id: command.id, ok: true, result: await run(command) }); }
    catch (error) { push({ id: command.id, ok: false, error: String(error?.message ?? error) }); }
    finally { state.busy = false; queueMicrotask(pump); }
  }
  state.dispatch = (command) => { state.heartbeat = Date.now(); state.queue.push(command); pump(); return { queued: true }; };
  state.drain = () => { state.heartbeat = Date.now(); const result = { phase: state.phase, outbox: state.outbox.splice(0) }; if (state.disposed) delete globalThis[STATE_KEY]; return result; };
  globalThis[STATE_KEY] = state;
  globalThis.__mobileCodexMainBridge = state;
  return { installed: true, pid: process.pid, stateKey: STATE_KEY };
})()""".replace("COMPATIBILITY", json.dumps(compatibility)).replace("ARBITRATION_SOURCE", arbitration_source).replace("RENDERER", json.dumps(renderer)).replace("STATE_KEY", json.dumps(state_key))
poll = "(() => { const state = globalThis[" + json.dumps(state_key) + "]; return JSON.stringify(state ? state.drain() : { phase: 'missing', outbox: [] }); })()"
dispatch_prefix = "(() => { const state = globalThis[" + json.dumps(state_key) + "]; return JSON.stringify(state ? state.dispatch(COMMAND) : { queued: false, error: 'bridge state missing' }); })()"

agent = r"""
const module = Process.getModuleByName('chrome.dll');
const exports = module.enumerateExports();
const native = (name, ret, params) => new NativeFunction(module.getExportByName(name), ret, params);
const current = new NativeFunction(exports.find((entry) => entry.name.startsWith('?GetCurrent@Isolate@v8')).address, 'pointer', []);
const open = native('napi_open_handle_scope', 'int', ['pointer', 'pointer']);
const close = native('napi_close_handle_scope', 'int', ['pointer', 'pointer']);
const makeString = native('napi_create_string_utf8', 'int', ['pointer', 'pointer', 'uint64', 'pointer']);
const run = native('napi_run_script', 'int', ['pointer', 'pointer', 'pointer']);
const read = native('napi_get_value_string_utf8', 'int', ['pointer', 'pointer', 'pointer', 'uint64', 'pointer']);
const isPending = native('napi_is_exception_pending', 'int', ['pointer', 'pointer']);
const clear = native('napi_get_and_clear_last_exception', 'int', ['pointer', 'pointer']);
let env = null, isolate = null, owner = null, busy = false, started = false, last = 0;
const commands = [];
function waitCommand() { recv('command', (message) => { commands.push(message.payload); waitCommand(); }); }
waitCommand();
function evaluate(code) {
  if (busy || !env || Process.getCurrentThreadId() !== owner || !current().equals(isolate) || Date.now() - last < 120) return false;
  const flag = Memory.alloc(1);
  if (isPending(env, flag) !== 0 || flag.readU8()) return false;
  busy = true; last = Date.now();
    const source = Memory.allocUtf8String(started ? code : BOOTSTRAP_EXPRESSION), scope = Memory.alloc(8), script = Memory.alloc(8), result = Memory.alloc(8), length = Memory.alloc(8);
  const opened = open(env, scope);
  try {
    if (opened !== 0) throw Error('napi scope status: ' + opened);
    if (makeString(env, source, new UInt64('18446744073709551615'), script) !== 0) throw Error('napi string creation failed');
    const status = run(env, script.readPointer(), result);
    if (status !== 0) { if (status === 10) clear(env, result); throw Error('napi execution status: ' + status); }
    started = true;
    if (read(env, result.readPointer(), ptr(0), 0, length) !== 0) throw Error('napi result length failed');
    const size = Number(length.readU64()) + 1;
    if (size > 16 * 1024 * 1024) throw Error('Desktop transport result exceeds 16 MiB');
    const buffer = Memory.alloc(size);
    if (read(env, result.readPointer(), buffer, size, length) !== 0) throw Error('napi result read failed');
    send({ stage: 'poll', value: JSON.parse(buffer.readUtf8String(Number(length.readU64()))) });
  } catch (error) { send({ stage: 'error', message: String(error) }); }
  finally { if (opened === 0) close(env, scope.readPointer()); busy = false; }
  return true;
}
function tick(candidate) {
  if (!env && candidate && !candidate.isNull()) {
    const candidateIsolate = candidate.add(NAPI_ENV_ISOLATE_OFFSET).readPointer();
    if (!current().equals(candidateIsolate)) return;
    env = candidate; isolate = candidateIsolate; owner = Process.getCurrentThreadId(); send({ stage: 'context-captured', threadId: owner, pid: Process.id });
  }
  if (!env || busy || Process.getCurrentThreadId() !== owner || !current().equals(isolate) || Date.now() - last < 120) return;
  if (!started) { evaluate(BOOTSTRAP_EXPRESSION); return; }
  if (commands.length) { if (evaluate(DISPATCH_PREFIX.replace('COMMAND', JSON.stringify(commands[0])))) commands.shift(); }
  else evaluate(POLL_EXPRESSION);
}
for (const name of ['napi_get_cb_info', 'napi_get_value_string_utf8', 'napi_create_string_utf8', 'napi_call_function']) {
  Interceptor.attach(module.getExportByName(name), { onEnter(args) { this.env = args[0]; this.skip = busy; }, onLeave(status) { if (!this.skip && status.toInt32() === 0) tick(this.env); } });
}
for (const entry of exports.filter((item) => item.name.startsWith('?Call@Function@v8') || item.name.startsWith('?MakeCallback@node') || item.name === 'uv_run')) Interceptor.attach(entry.address, { onLeave() { tick(); } });
send({ stage: 'armed', pid: Process.id, abi: 'napi-env-plus-8' });
""".replace('NAPI_ENV_ISOLATE_OFFSET', str(compatibility['napiEnvIsolateOffset'])).replace("BOOTSTRAP_EXPRESSION", json.dumps("JSON.stringify(" + bootstrap + ")")).replace("DISPATCH_PREFIX", json.dumps(dispatch_prefix)).replace("POLL_EXPRESSION", json.dumps(poll))

records = []
session = frida.attach(pid)
script = session.create_script(agent)
shutdown_done = threading.Event()
def on_message(message, data):
    if message.get("type") == "send":
        emit({"type": "agent", "payload": message.get("payload")})
        for result in message.get('payload', {}).get('value', {}).get('outbox', []):
            if result.get('id') == '__shutdown__':
                shutdown_done.set()
    elif message.get("type") == "error":
        emit({"type": "agent-error", "description": message.get("description", "Frida agent error")})
script.on("message", on_message)
script.load()
emit({"type": "ready", "pid": pid, "stateKey": state_key})

try:
    for line in sys.stdin:
        if not line.strip():
            continue
        command = json.loads(line)
        if not isinstance(command, dict) or not isinstance(command.get("id"), str):
            emit({"type": "error", "message": "Command id is required"})
            continue
        script.post({"type": "command", "payload": command})
finally:
    try:
        script.post({"type": "command", "payload": {"id": "__shutdown__", "op": "shutdown"}})
        shutdown_done.wait(5)
    except Exception:
        pass
    session.detach()
    emit({"type": "detached", "pid": pid})
