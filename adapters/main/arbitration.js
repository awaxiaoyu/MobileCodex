// Runs inside Desktop Main. One original server request can be claimed once
// across all renderers and the mobile renderer probe. Promise identity and
// synchronous exceptions remain those of the original handler.
export function installApprovalArbitration(handlers, channel, observedRequests, observe) {
  const original = handlers.get(channel);
  if (typeof original !== 'function') throw new Error('Missing Desktop message handler');
  const supported = new Set(['item/commandExecution/requestApproval', 'item/fileChange/requestApproval', 'item/permissions/requestApproval', 'item/tool/requestUserInput', 'mcpServer/elicitation/request']);
  const claimed = new Map();
  const key = (hostId, id) => JSON.stringify([hostId, id]);
  function wrapper(...args) {
    const message = args[1];
    if (message?.type !== 'mcp-response' || !message.response || !supported.has(message.requestMethod ?? observedRequests.get(key(message.hostId, message.response.id))?.method)) return Reflect.apply(original, this, args);
    const requestKey = key(message.hostId, message.response.id);
    if (claimed.has(requestKey)) return Promise.resolve({ mobileCodexAlreadyResponded: true, state: claimed.get(requestKey) });
    claimed.set(requestKey, 'submitting');
    try {
      const result = Reflect.apply(original, this, args);
      Promise.resolve(result).then(() => { claimed.set(requestKey, 'submitted'); observe?.({ requestId: message.response.id, hostId: message.hostId, state: 'submitted' }); }, () => { claimed.set(requestKey, 'unknown'); observe?.({ requestId: message.response.id, hostId: message.hostId, state: 'unknown' }); });
      if (claimed.size > 1000) claimed.delete(claimed.keys().next().value);
      return result;
    } catch (error) { claimed.set(requestKey, 'unknown'); throw error; }
  }
  handlers.set(channel, wrapper);
  return {
    hasClaimed(hostId, id) { return claimed.has(key(hostId, id)); },
    restore() { if (handlers.get(channel) === wrapper) handlers.set(channel, original); return handlers.get(channel) === original; },
  };
}
