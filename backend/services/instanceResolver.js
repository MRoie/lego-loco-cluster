/**
 * instanceResolver.js — map an instanceId to its VNC endpoint for the lens
 * bridge, decoupled from cluster discovery.
 *
 * Two strategies:
 *   - static: a fixed registry (LENS_INSTANCES) for the no-cluster case
 *     (Android/Termux, docker-compose, a single host). No k8s needed.
 *   - k8s:    delegate to a caller-provided async resolver (the existing
 *     instanceManager path) for the cluster case.
 *
 * LENS_INSTANCES formats (env or constructor):
 *   JSON:      {"local":{"host":"127.0.0.1","port":5901,"password":"..."}}
 *   JSON short:{"local":"127.0.0.1:5901"}
 *   CSV short: local=127.0.0.1:5901,other=127.0.0.1:5902
 */

function parseRegistry(spec) {
  if (!spec) return {};
  const trimmed = String(spec).trim();
  let raw;
  if (trimmed.startsWith('{')) {
    raw = JSON.parse(trimmed);
  } else {
    // CSV shorthand: id=host:port,id2=host:port
    raw = {};
    for (const pair of trimmed.split(',')) {
      const [id, target] = pair.split('=');
      if (id && target) raw[id.trim()] = target.trim();
    }
  }
  const out = {};
  for (const [id, val] of Object.entries(raw)) {
    if (typeof val === 'string') {
      const [host, portStr] = val.split(':');
      out[id] = { host, port: parseInt(portStr, 10) || 5901 };
    } else if (val && typeof val === 'object' && val.host) {
      out[id] = { host: val.host, port: parseInt(val.port, 10) || 5901, password: val.password };
    }
  }
  return out;
}

class InstanceResolver {
  /**
   * @param {object} opts
   * @param {string} [opts.mode] 'static' | 'k8s' | 'auto' (default from LENS_MODE or 'auto')
   * @param {string|object} [opts.registry] LENS_INSTANCES spec (default from env)
   * @param {(id:string)=>Promise<{host,port,password}|null>} [opts.k8sResolver]
   */
  constructor({ mode, registry, k8sResolver } = {}) {
    this.registry = parseRegistry(registry != null ? registry : process.env.LENS_INSTANCES);
    this.k8sResolver = k8sResolver || null;
    this.mode = mode || process.env.LENS_MODE || 'auto';
    if (this.mode === 'auto') {
      // Static wins when a registry is configured; else fall back to k8s.
      this.mode = Object.keys(this.registry).length > 0 ? 'static' : 'k8s';
    }
  }

  /** Resolve an instanceId → { host, port, password } | null. */
  async resolve(instanceId) {
    if (this.mode === 'static') {
      return this.registry[instanceId] || null;
    }
    // k8s / delegated
    if (!this.k8sResolver) return null;
    return this.k8sResolver(instanceId);
  }

  /** Known instance ids in static mode (empty in k8s mode — use discovery). */
  listStaticInstances() {
    return Object.keys(this.registry);
  }
}

module.exports = { InstanceResolver, parseRegistry };
