// Serialized into a verified Codex renderer by the local CDP loader. No network
// listener, credentials, arbitrary IPC or arbitrary-function RPC lives here.
export function installRendererProbe(win, options = {}) {
  const bridge = win.electronBridge;
  if (!bridge || typeof bridge.sendMessageFromView !== 'function') throw new Error('electronBridge is not available in this renderer');
  const ua = bridge.getDesktopUserAgent?.() ?? '';
  if (!ua.startsWith('Codex Desktop/26.1007.21434 ')) throw new Error('Unsupported Desktop version: renderer adapter is pinned to 26.1007.21434');
  const hostId = options.hostId ?? 'local';
  const allowControl = options.allowControl === true;
  if (win.__mobileCodexProbe) {
    const status = win.__mobileCodexProbe.status();
    if (status.hostId !== hostId || status.allowControl !== allowControl || status.allowApprovals !== (options.allowApprovals === true)) throw new Error('Dispose the existing probe before changing its host or control mode');
    return { installed: true, reused: true, version: '26.1007.21434' };
  }
  const requestRules = {
    'model/list': ['cursor', 'limit'],
    'thread/list': ['limit', 'cursor'],
    'thread/read': ['threadId', 'includeTurns'],
    'thread/start': ['projectId', 'cwd'],
    'thread/resume': ['threadId', 'excludeTurns'],
    'turn/start': ['threadId', 'input', 'model', 'effort', 'collaborationMode'],
    'turn/steer': ['threadId', 'expectedTurnId', 'input'],
    'turn/interrupt': ['threadId', 'turnId'],
  };
  const notifications = new Set(['item/agentMessage/delta', 'item/plan/delta', 'thread/started', 'thread/status/changed', 'turn/started', 'turn/completed', 'turn/diff/updated', 'turn/plan/updated', 'serverRequest/resolved', 'item/started', 'item/completed', 'error']);
  const events = [];
  const pending = new Map();
  const transfers = new Map();
  let stopped = false;
  let seq = 0;
  const publish = (event) => { events.push({ seq: ++seq, ...event }); if (events.length > 200) events.shift(); };
  function validChunkToken(token) {
    if (!token || typeof token !== 'object' || typeof token.type !== 'string') return false;
    if (['array-start', 'object-start', 'container-end', 'string-end'].includes(token.type)) return true;
    if (token.type === 'string-start') return token.target === 'key' || token.target === 'value';
    if (token.type === 'key' || token.type === 'string-chunk') return typeof token.value === 'string';
    if (token.type === 'value') return token.value === null || ['boolean', 'number', 'string'].includes(typeof token.value);
    return false;
  }
  function consumeChunk(data) {
    if (!data || data.marker !== 'codex-host-chunked-message-v1' || typeof data.transferId !== 'string' || !Number.isSafeInteger(data.sequence)) return data;
    let completed;
    if (data.kind === 'start') {
      transfers.set(data.transferId, { next: data.sequence + 1, stack: [], root: Symbol('unset'), stringChunks: null, stringTarget: null });
    } else {
      const transfer = transfers.get(data.transferId);
      if (!transfer || data.sequence !== transfer.next || (data.kind === 'chunk' && (!Array.isArray(data.tokens) || !data.tokens.every(validChunkToken)))) {
        transfers.delete(data.transferId);
        return undefined;
      }
      transfer.next++;
      if (data.kind === 'chunk') {
        for (const token of data.tokens) {
          if (token.type === 'array-start') { const value = []; saveChunkValue(transfer, value); transfer.stack.push({ type: 'array', value }); }
          else if (token.type === 'object-start') { const value = {}; saveChunkValue(transfer, value); transfer.stack.push({ type: 'object', value, key: null }); }
          else if (token.type === 'container-end') { if (!transfer.stack.pop()) { transfers.delete(data.transferId); return undefined; } }
          else if (token.type === 'key') { const top = transfer.stack.at(-1); if (!top || top.type !== 'object' || top.key !== null) { transfers.delete(data.transferId); return undefined; } top.key = token.value; }
          else if (token.type === 'value') saveChunkValue(transfer, token.value);
          else if (token.type === 'string-start') { if (transfer.stringChunks) { transfers.delete(data.transferId); return undefined; } transfer.stringChunks = []; transfer.stringTarget = token.target; }
          else if (token.type === 'string-chunk') { if (!transfer.stringChunks) { transfers.delete(data.transferId); return undefined; } transfer.stringChunks.push(token.value); }
          else if (token.type === 'string-end') {
            if (!transfer.stringChunks || !transfer.stringTarget) { transfers.delete(data.transferId); return undefined; }
            const value = transfer.stringChunks.join(''); const target = transfer.stringTarget;
            transfer.stringChunks = null; transfer.stringTarget = null;
            if (target === 'key') { const top = transfer.stack.at(-1); if (!top || top.type !== 'object' || top.key !== null) { transfers.delete(data.transferId); return undefined; } top.key = value; }
            else saveChunkValue(transfer, value);
          }
        }
      } else if (data.kind === 'end') {
        transfers.delete(data.transferId);
        if (transfer.stack.length || transfer.stringChunks || typeof transfer.root === 'symbol') return undefined;
        completed = transfer.root;
      }
    }
    bridge.acknowledgeChunkedMessage?.(data.transferId, data.sequence);
    return completed;
  }
  function saveChunkValue(transfer, value) {
    const top = transfer.stack.at(-1);
    if (!top) { if (typeof transfer.root !== 'symbol') throw new Error('Chunked message contained multiple root values'); transfer.root = value; return; }
    if (top.type === 'array') { top.value.push(value); return; }
    if (top.key === null) throw new Error('Chunked message object value had no key');
    Object.defineProperty(top.value, top.key, { configurable: true, enumerable: true, writable: true, value }); top.key = null;
  }
  function normalizeMessage(value) {
    if (!value || typeof value !== 'object') return value;
    return value.marker === 'codex-host-chunked-message-v1' ? consumeChunk(value) : value;
  }
  function onMessage(event) {
    if (stopped || event.source && event.source !== win) return;
    const data = normalizeMessage(event.data);
    if (!data) return;
    if (!data || typeof data !== 'object' || data.hostId !== hostId) return;
    if (data.type === 'mcp-response' && pending.has(data.message?.id)) {
      const p = pending.get(data.message.id); pending.delete(data.message.id); clearTimeout(p.timer);
      if (data.message.error) p.reject(new Error(data.message.error.message ?? 'Desktop request failed'));
      else p.resolve(data.message.result);
    } else if (data.type === 'mcp-notification' && notifications.has(data.method)) {
      publish({ kind: 'notification', method: data.method, params: data.params });
    } else if (data.type === 'mcp-request' && typeof data.request?.method === 'string') {
      // Observe only metadata. Desktop retains ownership of approvals until the
      // shared response arbitration path has passed an integration test.
      if (options.allowApprovals === true) publish({ kind: 'server.request', id: data.request.id, method: data.request.method, params: data.request.params });
      else publish({ kind: 'server.request.observed', requestId: data.request.id, method: data.request.method, threadId: data.request.params?.threadId, turnId: data.request.params?.turnId });
    }
  }
  win.addEventListener('message', onMessage);
  const probe = {
    status() { return { version: '26.1007.21434', hostId, allowControl, allowApprovals: options.allowApprovals === true, pending: pending.size, lastSeq: seq, stopped }; },
    drain() { return events.splice(0); },
    async respond(id, method, result, threadId) {
      if (stopped || options.allowApprovals !== true) throw new Error('Approval replies are disabled');
      if (!['item/commandExecution/requestApproval', 'item/fileChange/requestApproval', 'item/permissions/requestApproval', 'item/tool/requestUserInput', 'mcpServer/elicitation/request'].includes(method)) throw new Error('Approval method is not registered');
      const delivery = await bridge.sendMessageFromView({ type: 'mcp-response', hostId, requestMethod: method, threadId, response: { id, result } });
      if (delivery?.mobileCodexAlreadyResponded) throw new Error('Server request was already answered on Desktop');
      return { submitted: true };
    },
    call(method, params = {}) {
      if (stopped) return Promise.reject(new Error('Renderer adapter has been disposed'));
      const allowed = Object.hasOwn(requestRules, method) ? requestRules[method] : undefined;
      if (!allowed) return Promise.reject(new Error('Method is not registered'));
      if ((method.startsWith('turn/') || method === 'thread/start' || method === 'thread/resume') && !allowControl) return Promise.reject(new Error('Control is disabled for this probe'));
      if (!params || Array.isArray(params) || typeof params !== 'object') return Promise.reject(new Error('Invalid params'));
      for (const key of Object.keys(params)) if (!allowed.includes(key)) return Promise.reject(new Error('Field is not allowed: ' + key));
      if (method.startsWith('turn/') || method === 'thread/read') {
        if (typeof params.threadId !== 'string' || !params.threadId.trim()) return Promise.reject(new Error('threadId is required'));
      }
      if (method === 'turn/interrupt' && (typeof params.turnId !== 'string' || !params.turnId.trim())) return Promise.reject(new Error('turnId is required'));
      if (method === 'turn/steer' && (typeof params.expectedTurnId !== 'string' || !params.expectedTurnId.trim())) return Promise.reject(new Error('expectedTurnId is required'));
      if (method === 'turn/start' || method === 'turn/steer') {
        if (!Array.isArray(params.input) || !params.input.length || params.input.some((i) => !i || i.type !== 'text' || typeof i.text !== 'string' || !i.text.trim() || Object.keys(i).some((k) => !['type', 'text'].includes(k)))) return Promise.reject(new Error('P0 requires text input'));
      }
      const id = 'mobile-bridge-' + win.crypto.randomUUID();
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { pending.delete(id); reject(new Error('Desktop response timed out; result is unknown')); }, 15000);
        pending.set(id, { resolve, reject, timer });
        // invoke completion is delivery acknowledgement, not the app-server
        // result. Actual results arrive via the mcp-response window event.
        Promise.resolve(bridge.sendMessageFromView({ type: 'mcp-request', hostId, request: { id, method, params } })).catch((error) => {
          clearTimeout(timer); pending.delete(id); reject(error);
        });
      });
    },
    dispose() {
      stopped = true; win.removeEventListener('message', onMessage);
      for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('Renderer adapter unloaded; request result may be unknown')); }
      pending.clear(); events.length = 0; transfers.clear(); delete win.__mobileCodexProbe;
      return { disposed: true };
    },
  };
  win.__mobileCodexProbe = probe;
  return { installed: true, reused: false, version: '26.1007.21434', hostId, allowControl };
}
