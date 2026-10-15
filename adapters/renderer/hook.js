// Use only on a reachable, writable in-process business object. Electron's
// contextBridge object may be frozen; the loader does not try to override it.
export function hookMethod(target, name, observe) {
  const original = target[name];
  if (typeof original !== 'function') throw new Error('Hook target is not a function');
  function wrapped(...args) {
    try { observe({ phase: 'before', args }); } catch { /* observer cannot break the business operation */ }
    try {
      const result = Reflect.apply(original, this, args);
      try { observe({ phase: 'returned', result }); } catch {}
      return result; // Preserve Promise identity, cancellation handle and type.
    } catch (error) {
      try { observe({ phase: 'threw', error }); } catch {}
      throw error;
    }
  }
  target[name] = wrapped;
  if (target[name] !== wrapped) throw new Error('Hook target is not writable');
  return () => { if (target[name] === wrapped) target[name] = original; };
}
