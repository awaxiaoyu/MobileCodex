// Serialized into a verified Codex renderer by the local CDP loader. No network
// listener, credentials, arbitrary IPC or arbitrary-function RPC lives here.
export function installRendererProbe(win, options = {}) {
  const bridge = win.electronBridge;
  if (!bridge || typeof bridge.sendMessageFromView !== 'function') throw new Error('electronBridge is not available in this renderer');
  const ua = bridge.getDesktopUserAgent?.() ?? '';
  if (!ua.startsWith('Codex Desktop/26.1007.21434 ')) throw new Error('Unsupported Desktop version: renderer adapter is pinned to 26.1007.21434');
  const hostId = options.hostId ?? 'local';
  const policy = { allowControl: options.allowControl === true, allowApprovals: options.allowApprovals === true };
  if (win.__mobileCodexProbe) {
    const status = win.__mobileCodexProbe.status();
    if (status.hostId !== hostId || status.allowControl !== policy.allowControl || status.allowApprovals !== policy.allowApprovals) throw new Error('Dispose the existing probe before changing its host or control mode');
    const settings = options.settingsUi ? installBridgeSettingsUi(win, options.settingsUi) : win.__mobileCodexBridgeSettings?.status?.();
    return { installed: true, reused: true, version: '26.1007.21434', settings };
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
      if (policy.allowApprovals) publish({ kind: 'server.request', id: data.request.id, method: data.request.method, params: data.request.params });
      else publish({ kind: 'server.request.observed', requestId: data.request.id, method: data.request.method, threadId: data.request.params?.threadId, turnId: data.request.params?.turnId });
    }
  }
  win.addEventListener('message', onMessage);
  const probe = {
    status() { return { version: '26.1007.21434', hostId, allowControl: policy.allowControl, allowApprovals: policy.allowApprovals, pending: pending.size, lastSeq: seq, stopped }; },
    setPolicy(name, enabled) {
      if (!['allow-control', 'approval-forwarding'].includes(name) || typeof enabled !== 'boolean') throw new Error('Unsupported renderer policy');
      if (name === 'allow-control') policy.allowControl = enabled;
      if (name === 'approval-forwarding') policy.allowApprovals = enabled;
      return this.status();
    },
    drain() { return events.splice(0); },
    async respond(id, method, result, threadId) {
      if (stopped || !policy.allowApprovals) throw new Error('Approval replies are disabled');
      if (!['item/commandExecution/requestApproval', 'item/fileChange/requestApproval', 'item/permissions/requestApproval', 'item/tool/requestUserInput', 'mcpServer/elicitation/request'].includes(method)) throw new Error('Approval method is not registered');
      const delivery = await bridge.sendMessageFromView({ type: 'mcp-response', hostId, requestMethod: method, threadId, response: { id, result } });
      if (delivery?.mobileCodexAlreadyResponded) throw new Error('Server request was already answered on Desktop');
      return { submitted: true };
    },
    call(method, params = {}) {
      if (stopped) return Promise.reject(new Error('Renderer adapter has been disposed'));
      const allowed = Object.hasOwn(requestRules, method) ? requestRules[method] : undefined;
      if (!allowed) return Promise.reject(new Error('Method is not registered'));
      if ((method.startsWith('turn/') || method === 'thread/start' || method === 'thread/resume') && !policy.allowControl) return Promise.reject(new Error('Control is disabled for this probe'));
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
      pending.clear(); events.length = 0; transfers.clear(); win.__mobileCodexBridgeSettings?.dispose?.(); delete win.__mobileCodexProbe;
      return { disposed: true };
    },
  };
  win.__mobileCodexProbe = probe;
  const settings = options.settingsUi ? installBridgeSettingsUi(win, options.settingsUi) : { installed: false, reason: 'settings_ui_not_requested' };
  return { installed: true, reused: false, version: '26.1007.21434', hostId, allowControl: policy.allowControl, allowApprovals: policy.allowApprovals, settings };
}

// The Desktop does not expose a stable React settings registry. This adapter
// only installs when the known settings DOM capability is present, and uses a
// cloned native menu item plus CSS variables/classes from that page.
export function detectSettingsCapability(win) {
  const document = win?.document;
  if (!document?.querySelectorAll) return { supported: false, code: 'renderer_dom_unavailable', reason: 'Desktop settings DOM is unavailable' };
  const exactText = (element) => String(element?.textContent ?? '').replace(/[\u2318\u2325]|Alt\+|Ctrl\+|Shift\+/gi, ' ').replace(/[>›]/g, ' ').replace(/\s+/g, ' ').trim();
  const itemSelector = 'button, [role="menuitem"], [data-radix-collection-item], a, li, div';
  const menuItem = (element) => {
    const text = exactText(element);
    return text.length <= 80 && /^(设置|Settings|帮助|Help|Show Pet)(?:\s|$)/i.test(text);
  };
  const helpItem = (items) => items.find((element) => /^(帮助|Help)(?:\s|$)/i.test(exactText(element)));
  const menuForItems = (items) => {
    for (const item of items) {
      let parent = item.parentElement;
      for (let depth = 0; parent && depth < 6; depth++, parent = parent.parentElement) {
        const text = exactText(parent);
        if (text.length > 0 && text.length <= 500 && /(设置|Settings)/.test(text) && /(帮助|Help)/.test(text)) {
          const children = [...parent.querySelectorAll(itemSelector)].filter(menuItem);
          if (children.length >= 2) return { menu: parent, anchor: item, items: children, help: helpItem(children) };
        }
      }
    }
    return undefined;
  };
  // The account popup is often rendered inside a persistent aside/nav. Prefer
  // the actual labeled item group so a broad shell cannot mask the popup.
  const labelMatch = menuForItems([...document.querySelectorAll(itemSelector)].filter(menuItem));
  if (labelMatch) return { supported: true, ...labelMatch, template: labelMatch.anchor, reason: 'Settings popup recognized by menu labels' };
  const containers = [...document.querySelectorAll('[role="menu"], nav, aside, [data-testid*="settings"]')];
  const menu = containers.find((container) => {
    const text = String(container.textContent ?? '').toLowerCase();
    return text.includes('general') || text.includes('appearance') || text.includes('设置');
  });
  if (!menu) {
    const labelMatch = menuForItems([...document.querySelectorAll(itemSelector)].filter(menuItem));
    if (labelMatch) return { supported: true, ...labelMatch, template: labelMatch.anchor, reason: 'Settings popup recognized by menu labels' };
    const trigger = [...document.querySelectorAll('button, [role="button"], [aria-label]')].find((element) => {
      const label = ((element.getAttribute?.('aria-label') ?? '') + ' ' + String(element.textContent ?? '')).toLowerCase();
      return /\bsettings\b|设置/.test(label);
    });
    // The account/gear popup is created lazily. For the pinned Desktop build,
    // keep a deferred watcher and require the labeled native items before any
    // insertion; this handles a closed menu without guessing a private React
    // component or injecting into unrelated content.
    return { supported: true, deferred: true, trigger, reason: 'Settings menu will be checked after it opens' };
  }
  if (typeof menu.querySelectorAll !== 'function') {
    const labelMatch = menuForItems([...document.querySelectorAll(itemSelector)].filter(menuItem));
    if (labelMatch) return { supported: true, ...labelMatch, template: labelMatch.anchor, reason: 'Settings popup recognized by menu labels' };
    return { supported: false, code: 'settings_item_not_found', reason: 'Desktop settings menu has no reusable item' };
  }
  const items = [...menu.querySelectorAll(itemSelector)];
  const template = items.find((item) => String(item.textContent ?? '').trim().length > 0);
  if (!template) return { supported: false, code: 'settings_item_not_found', reason: 'Desktop settings menu has no reusable item' };
  return { supported: true, menu, template };
}

export function featureToggleState(feature) {
  return {
    checked: feature?.enabled === true,
    disabled: feature?.editable !== true,
    title: feature?.reason ?? (feature?.editable === true ? '实时生效' : '只读状态；修改需要重启 Bridge'),
  };
}

export function installBridgeSettingsUi(win, options = {}) {
  const bridge = win?.electronBridge;
  const expectedVersion = options.version ?? '26.1007.21434';
  const ua = bridge?.getDesktopUserAgent?.() ?? '';
  if (!ua.startsWith('Codex Desktop/' + expectedVersion + ' ')) return { installed: false, code: 'unsupported_version', reason: 'Bridge settings UI is pinned to Desktop ' + expectedVersion };
  if (win.__mobileCodexBridgeSettings) {
    const existing = win.__mobileCodexBridgeSettings;
    if (!options.endpoint || existing.matches?.(options)) return existing.status();
    // A Bridge restart creates a fresh short-lived UI session. Reuse the
    // renderer probe, but replace the settings controller so it does not keep
    // sending the expired session to the new local server.
    existing.dispose?.();
  }
  const capability = detectSettingsCapability(win);
  const deferred = capability.deferred === true || (!capability.supported && capability.code === 'settings_menu_not_found');
  if (!capability.supported && !deferred) return { installed: false, code: capability.code, reason: capability.reason };
  const document = win.document;
  let item;
  let menu;
  const menuItemSelector = 'button, [role="menuitem"], [data-radix-collection-item], a, li, div';
  const menuText = (element) => String(element?.textContent ?? '').replace(/[\u2318\u2325]|Alt\+|Ctrl\+|Shift\+/gi, ' ').replace(/[>›]/g, ' ').replace(/\s+/g, ' ').trim();
  const panel = document.createElement('div');
  panel.dataset.mobileCodexBridgePanel = 'true';
  panel.setAttribute('aria-label', 'Bridge 设置');
  panel.setAttribute('role', 'presentation');
  panel.hidden = true;
  panel.style.cssText = 'position:fixed;inset:0;z-index:2147483000;display:flex;align-items:center;justify-content:center;padding:24px;background:rgba(0,0,0,.58);color:var(--text-primary,CanvasText);font:inherit;';
  const dialog = document.createElement('section');
  dialog.setAttribute('role', 'dialog');
  dialog.setAttribute('aria-modal', 'true');
  dialog.setAttribute('aria-labelledby', 'mobile-codex-bridge-title');
  dialog.style.cssText = 'display:flex;flex-direction:column;width:min(760px,100%);max-height:min(760px,calc(100vh - 48px));overflow:hidden;background:var(--background-primary,#202020);border:1px solid var(--border-medium,rgba(255,255,255,.14));border-radius:12px;box-shadow:0 24px 80px rgba(0,0,0,.42);';
  panel.append(dialog);
  const header = document.createElement('header');
  header.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:16px;padding:16px 20px;border-bottom:1px solid var(--border-medium,rgba(255,255,255,.1));flex:0 0 auto;';
  const heading = document.createElement('h1');
  heading.id = 'mobile-codex-bridge-title'; heading.textContent = 'Bridge 设置';
  heading.style.cssText = 'margin:0;font-size:18px;font-weight:600;line-height:24px;';
  header.append(heading);
  const closeButton = document.createElement('button');
  closeButton.type = 'button'; closeButton.textContent = '\u00d7'; closeButton.setAttribute('aria-label', '关闭 Bridge 设置'); closeButton.title = '关闭';
  closeButton.style.cssText = 'display:inline-flex;align-items:center;justify-content:center;width:32px;height:32px;padding:0;border:0;border-radius:6px;background:transparent;color:inherit;font-size:24px;line-height:1;cursor:pointer;';
  header.append(closeButton);
  dialog.append(header);
  const content = document.createElement('div');
  content.style.cssText = 'min-width:0;overflow:auto;padding:18px 20px 24px;';
  dialog.append(content);
  const live = document.createElement('div');
  content.append(live);
  const pairing = document.createElement('pre');
  pairing.dataset.mobileCodexPairing = 'true';
  pairing.hidden = true;
  pairing.style.cssText = 'margin:12px 0 0;padding:12px;border:1px solid var(--border-medium,rgba(255,255,255,.14));border-radius:8px;white-space:pre-wrap;word-break:break-word;font:12px/1.5 var(--font-mono,ui-monospace,monospace);';
  content.append(pairing);
  const pairingQr = document.createElement('img');
  pairingQr.dataset.mobileCodexPairingQr = 'true';
  pairingQr.hidden = true;
  pairingQr.alt = '手机配对二维码';
  pairingQr.style.cssText = 'display:block;width:min(280px,100%);height:auto;margin:14px auto 0;padding:12px;background:#fff;border-radius:8px;image-rendering:auto;';
  const session = String(options.token ?? '');
  const endpoint = String(options.endpoint ?? '');
  const state = { open: false, timer: undefined, last: undefined, signature: undefined };
  const settingsPending = new Map();
  const request = (action, payload = {}) => {
    if (!bridge || typeof bridge.sendMessageFromView !== 'function') return Promise.reject(new Error('Desktop settings IPC is unavailable'));
    const id = 'mobile-settings-' + win.crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = win.setTimeout(() => { settingsPending.delete(id); reject(new Error('Desktop settings request timed out')); }, 15000);
      settingsPending.set(id, { resolve, reject, timer });
      Promise.resolve(bridge.sendMessageFromView({ type: 'mobile-codex-settings-request', id, action, payload })).catch((error) => {
        win.clearTimeout(timer); settingsPending.delete(id); reject(error);
      });
    });
  };
  const api = async (path, init = {}) => {
    if (path === '/ui/status') return await request('status');
    if (path === '/ui/pairing') return await request('pairing');
    if (path === '/ui/feature') return await request('feature', JSON.parse(init.body ?? '{}'));
    if (path === '/ui/devices/revoke') {
      let value = {};
      try { value = JSON.parse(init.body ?? '{}'); } catch { throw new Error('Invalid device revoke request'); }
      return await request('revoke', value);
    }
    throw new Error('Unsupported Bridge settings request');
  };
  const text = (value) => value === undefined || value === null || value === '' ? '—' : String(value);
  const statusText = (value) => ({ running: '运行中', connected: '已连接', listening: '监听中', stopped: '已停止', disabled: '未启用', enabled: '已启用', active: '活动', revoked: '已撤销', installed: '已安装', 'not-installed': '未安装', PASS: '通过', WARN: '警告', FAIL: '失败' }[String(value)] ?? text(value));
  const statusTone = (value) => {
    const normalized = String(value ?? '').toLowerCase();
    if (['pass', 'running', 'connected', 'listening', 'enabled', 'active', 'installed', '通过', '运行中', '已连接', '监听中', '已启用', '活动', '已安装'].includes(normalized)) return 'success';
    if (['fail', 'error', 'disconnected', 'unavailable', '失败', '错误', '不可用'].includes(normalized)) return 'danger';
    if (['warn', 'warning', 'not-installed', 'stopped', '警告', '未安装', '已停止'].includes(normalized)) return 'warning';
    return '';
  };
  const featureLabel = (key, feature) => feature?.label ?? ({ 'control-mode': '控制模式（allow-control）', 'approval-forwarding': '审批转发', 'event-stream': '事件流', wss: 'WSS 服务', 'frida-hooks': 'Frida hooks' }[key] ?? key);
  const row = (label, value, detail, tone) => {
    const element = document.createElement('div');
    element.style.cssText = 'display:grid;grid-template-columns:minmax(135px,.42fr) minmax(0,1fr);gap:12px;align-items:baseline;padding:9px 0;border-bottom:1px solid color-mix(in srgb,currentColor 12%,transparent);';
    const key = document.createElement('strong'); key.textContent = label;
    const valueElement = document.createElement('span'); valueElement.style.cssText = 'min-width:0;overflow-wrap:anywhere;'; valueElement.textContent = text(value);
    const resolvedTone = tone ?? statusTone(value);
    if (resolvedTone === 'success') valueElement.style.color = 'var(--text-success,#32d583)';
    if (resolvedTone === 'danger') valueElement.style.color = 'var(--text-danger,#ff6b6b)';
    if (resolvedTone === 'warning') valueElement.style.color = 'var(--text-warning,#f4b740)';
    element.append(key, valueElement);
    if (detail) { const note = document.createElement('small'); note.textContent = ' ' + detail; valueElement.append(note); }
    return element;
  };
  const section = (title) => { const element = document.createElement('section'); element.style.cssText = 'margin:0 0 22px;'; const heading = document.createElement('h2'); heading.textContent = title; heading.style.cssText = 'margin:0 0 4px;font-size:13px;font-weight:600;color:var(--text-secondary,var(--text-primary,CanvasText));'; element.append(heading); return element; };
  function renderStatus(value) {
    live.replaceChildren();
    const toolbar = document.createElement('div'); toolbar.style.cssText = 'display:flex;justify-content:flex-end;margin:0 0 12px;';
    const refresh = document.createElement('button'); refresh.type = 'button'; refresh.textContent = '刷新'; refresh.style.cssText = 'padding:6px 10px;border:1px solid var(--border-medium,rgba(255,255,255,.18));border-radius:6px;background:var(--background-secondary,rgba(255,255,255,.06));color:inherit;font:inherit;cursor:pointer;'; refresh.addEventListener('click', () => void refreshStatus()); toolbar.append(refresh); live.append(toolbar);
    const pairingSection = section('手机配对');
    const pairingHint = document.createElement('p'); pairingHint.textContent = '二维码只包含一次性配对信息，有效期有限且只能使用一次。'; pairingHint.style.cssText = 'margin:0 0 10px;color:var(--text-secondary,var(--text-primary,CanvasText));'; pairingSection.append(pairingHint);
    const pair = document.createElement('button'); pair.type = 'button'; pair.textContent = '生成一次性配对二维码'; pair.style.cssText = 'padding:7px 11px;border:1px solid var(--border-medium,rgba(255,255,255,.18));border-radius:6px;background:var(--background-secondary,rgba(255,255,255,.06));color:inherit;font:inherit;cursor:pointer;'; pair.addEventListener('click', async () => { const pairingValue = await api('/ui/pairing', { method: 'POST' }); pairing.hidden = false; pairingQr.hidden = !pairingValue.qr; pairingQr.src = pairingValue.qr ?? ''; pairing.textContent = JSON.stringify({ url: pairingValue.url, fingerprint: pairingValue.fingerprint, id: pairingValue.id, secret: pairingValue.secret, expiresAt: pairingValue.expiresAt }, null, 2); }); pairingSection.append(pair, pairingQr, pairing);
    live.append(pairingSection);
    const devices = section('手机配对与设备');
    for (const device of (value.devices ?? []).filter((entry) => !entry.revokedAt)) {
      const state = device.connected ? '在线' : '信任';
      const detail = [device.lastSeenAt ? '最近连接 ' + device.lastSeenAt : '尚未连接', device.lastAddress].filter(Boolean).join(' · ');
      const deviceRow = row(device.name, state, detail || device.createdAt, device.connected ? 'success' : undefined);
      const revoke = document.createElement('button'); revoke.type = 'button'; revoke.textContent = '撤销'; revoke.addEventListener('click', async () => { await api('/ui/devices/revoke', { method: 'POST', body: JSON.stringify({ deviceId: device.id }) }); await refreshStatus(true); }); deviceRow.append(revoke);
      devices.append(deviceRow);
    }
    live.append(devices);
    const bridgeSection = section('运行状态');
    bridgeSection.append(row('Bridge', statusText(value.bridge?.status), value.bridge?.version));
    bridgeSection.append(row('Backend', (value.backends ?? []).map((item) => item.id + '（' + statusText(item.status) + '，generation ' + item.generation + '）').join('、') || '—'));
    bridgeSection.append(row('WSS', statusText(value.wss?.status), [value.wss?.url, value.wss?.fingerprint ? 'fingerprint ' + value.wss.fingerprint : undefined].filter(Boolean).join(' ')));
    bridgeSection.append(row('信任设备', value.devices?.filter((device) => !device.revokedAt).length ?? 0));
    bridgeSection.append(row('在线设备', value.devices?.filter((device) => !device.revokedAt && device.connected).length ?? 0));
    bridgeSection.append(row('事件流', (value.streams ?? []).map((stream) => stream.backendId + '：#' + stream.seq + '（缓存 ' + stream.cachedEvents + ' 条，' + stream.cachedBytes + ' bytes）').join('、') || (value.eventStreamEnabled === false ? '已停用' : '空闲')));
    live.append(bridgeSection);
    const paramsSection = section('Bridge 参数');
    const parameterLabels = { 'listen address': '监听地址', 'admin port': '管理端口', 'mobile listen address': '手机监听地址', 'mobile port': '手机端口', 'public URL': '公网 Pairing URL', workspace: 'Workspace', TLS: 'TLS', backend: 'Backend' };
    for (const [label, parameter] of Object.entries(value.parameters ?? {})) paramsSection.append(row(parameterLabels[label] ?? label, parameter.value, parameter.restartRequired ? '修改后需要重启 Bridge' : undefined));
    live.append(paramsSection);
    const switches = section('功能开关');
    for (const [key, feature] of Object.entries(value.features ?? {})) {
      const label = featureLabel(key, feature);
      const toggleState = featureToggleState(feature);
      const editable = !toggleState.disabled;
      const initialEnabled = toggleState.checked;
      const featureRow = row(label, initialEnabled ? '已启用' : '已停用', feature.reason ?? (editable ? '实时生效' : '只读状态；修改需要重启 Bridge'), initialEnabled ? 'success' : '');
      const toggle = document.createElement('input');
      toggle.type = 'checkbox';
      toggle.checked = toggleState.checked;
      toggle.disabled = toggleState.disabled;
      toggle.setAttribute('aria-label', label);
      toggle.title = toggleState.title;
      if (editable) {
        toggle.addEventListener('change', async () => {
          const requested = toggle.checked;
          toggle.disabled = true;
          try {
            await api('/ui/feature', { method: 'POST', body: JSON.stringify({ name: key, enabled: requested }) });
            await refreshStatus(true);
          } catch (error) {
            toggle.checked = !requested;
            const reason = error instanceof Error ? error.message : String(error);
            const errorNote = document.createElement('small');
            errorNote.dataset.mobileCodexFeatureError = key;
            errorNote.textContent = ' 修改失败：' + reason;
            errorNote.style.color = 'var(--text-danger,#ff6b6b)';
            featureRow.append(errorNote);
            toggle.disabled = false;
          }
        });
      }
      featureRow.append(toggle);
      switches.append(featureRow);
    }
    live.append(switches);
    const hooks = section('注入与 Hooks');
    hooks.append(row('Frida', statusText(value.frida?.helper?.status), value.frida?.helper?.pid ? 'PID ' + value.frida.helper.pid : undefined));
    hooks.append(row('Hooks', value.frida?.injection?.hooksInstalled ? '已安装' : '未安装', value.frida?.injection?.hooksRestored ? '上次关闭时已恢复' : undefined));
    live.append(hooks);
    const settingsUi = value.frida?.settingsUi;
    live.append(row('设置入口', settingsUi?.menuInstalled ? '已安装' : settingsUi?.installed ? '等待设置菜单' : '降级模式', settingsUi?.reason));
    const env = section('环境检测');
    for (const check of value.environment ?? []) env.append(row(check.name, statusText(check.status), check.reason, check.status === 'PASS' ? 'success' : check.status === 'FAIL' ? 'danger' : 'warning'));
    live.append(env);
  }
  function renderUnavailable(error) {
    live.replaceChildren();
    const toolbar = document.createElement('div'); toolbar.style.cssText = 'display:flex;justify-content:flex-end;margin:0 0 12px;';
    const refresh = document.createElement('button'); refresh.type = 'button'; refresh.textContent = '重试'; refresh.style.cssText = 'padding:6px 10px;border:1px solid var(--border-medium,rgba(255,255,255,.18));border-radius:6px;background:var(--background-secondary,rgba(255,255,255,.06));color:inherit;font:inherit;cursor:pointer;'; refresh.addEventListener('click', () => void refreshStatus()); toolbar.append(refresh); live.append(toolbar);
    const status = section('Bridge 状态');
    status.append(row('连接', '不可用', error, 'danger'));
    const note = document.createElement('p'); note.textContent = '本地 Bridge 没有返回状态。请确认 Bridge 进程正在运行后重试。'; note.style.cssText = 'margin:12px 0 0;color:var(--text-secondary,var(--text-primary,CanvasText));'; status.append(note);
    live.append(status);
  }
  async function refreshStatus(force = false) {
    try {
      const value = await api('/ui/status');
      const signature = JSON.stringify(value);
      if (!force && signature === state.signature) return;
      state.signature = signature; state.last = value; renderStatus(value);
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      const signature = 'unavailable:' + reason;
      if (signature !== state.signature) { state.signature = signature; renderUnavailable(reason); }
    }
  }
  async function diagnose() {
    try { await request('status'); return { ok: true, transport: 'desktop-main-hook' }; }
    catch (error) { return { ok: false, transport: 'desktop-main-hook', error: error instanceof Error ? error.message : String(error), name: error?.name }; }
  }
  const open = () => { state.open = true; panel.hidden = false; void refreshStatus(); if (!state.timer) state.timer = win.setInterval(() => { if (state.open) void refreshStatus(); }, 2000); };
  const close = () => { state.open = false; panel.hidden = true; };
  const onKeyDown = (event) => { if (state.open && event.key === 'Escape') close(); };
  closeButton.addEventListener('click', close);
  panel.addEventListener('click', (event) => { if (event.target === panel) close(); });
  document.addEventListener?.('keydown', onKeyDown);
  let observer;
  const setMenuItemLabel = (element, label) => {
    let firstText;
    const visit = (node) => {
      for (const child of [...(node.childNodes ?? [])]) {
        if (child.nodeType === 3 && String(child.textContent ?? '').trim()) {
          firstText ??= child;
          if (/(设置|Settings|帮助|Help)/i.test(String(child.textContent))) { child.textContent = label; return true; }
        }
        if (visit(child)) return true;
      }
      return false;
    };
    if (!visit(element)) { if (firstText) firstText.textContent = label; else { const textNode = document.createElement('span'); textNode.textContent = label; element.append(textNode); } }
  };
  const installMenuItem = () => {
    const next = detectSettingsCapability(win);
    if (!next.supported || !next.menu || !next.template) return;
    menu = next.menu;
    if (!item) {
      item = next.template.cloneNode(true);
      item.removeAttribute?.('id');
      item.dataset.mobileCodexBridge = 'true';
      item.setAttribute?.('aria-label', 'Mobile Codex');
      item.title = 'Mobile Codex';
      setMenuItemLabel(item, 'Mobile Codex');
      item.addEventListener('click', (event) => { event.preventDefault(); event.stopPropagation(); open(); });
      const nativeClass = next.template.className;
      if (typeof nativeClass === 'string' && nativeClass) panel.className = nativeClass;
    }
    if (item.parentNode !== menu) {
      const help = next.help ?? [...menu.querySelectorAll(menuItemSelector)].find((element) => /^(帮助|Help)(?:\s|$)/i.test(menuText(element)));
      if (help) menu.insertBefore(item, help); else menu.append(item);
    }
  };
  const onDocumentClick = () => win.setTimeout(installMenuItem, 0);
  document.addEventListener?.('click', onDocumentClick, true);
  document.body?.append(panel);
  installMenuItem();
  if (win.MutationObserver && document.body) {
    observer = new win.MutationObserver(() => installMenuItem());
    observer.observe(document.body, { childList: true, subtree: true });
  }
  const controller = {
    status: () => ({ installed: true, menuInstalled: Boolean(item?.parentNode), capability: { supported: true, deferred: deferred || capability.deferred === true }, open: state.open }),
    matches: (next) => String(next?.endpoint ?? '') === endpoint && String(next?.token ?? '') === session,
    resolve: (id, value, error) => {
      const pending = settingsPending.get(id);
      if (!pending) return { resolved: false };
      settingsPending.delete(id); win.clearTimeout(pending.timer);
      if (error) pending.reject(new Error(String(error))); else pending.resolve(value);
      return { resolved: true };
    },
    diagnose,
    open, close,
    dispose() { if (state.timer) win.clearInterval(state.timer); for (const pending of settingsPending.values()) { win.clearTimeout(pending.timer); pending.reject(new Error('Desktop settings UI unloaded')); } settingsPending.clear(); observer?.disconnect(); document.removeEventListener?.('click', onDocumentClick, true); document.removeEventListener?.('keydown', onKeyDown); item?.remove(); panel.remove(); delete win.__mobileCodexBridgeSettings; return { disposed: true }; },
  };
  win.__mobileCodexBridgeSettings = controller;
  return controller.status();
}
