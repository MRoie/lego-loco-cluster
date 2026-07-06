/**
 * Simple in-memory sliding window rate limiter.
 * Returns Express middleware.
 *
 * @param {{ windowMs?: number, max?: number }} options
 *   windowMs — sliding window size in milliseconds (default 60 000)
 *   max      — maximum requests allowed per window (default 30)
 */
function rateLimit({ windowMs = 60_000, max = 30 } = {}) {
  // Map<clientKey, number[]>  — stores request timestamps per client
  const clients = new Map();

  // Periodically prune stale entries to prevent memory growth
  const pruneInterval = setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [key, timestamps] of clients) {
      const filtered = timestamps.filter(t => t > cutoff);
      if (filtered.length === 0) {
        clients.delete(key);
      } else {
        clients.set(key, filtered);
      }
    }
  }, windowMs);

  // Allow GC if the server holds no other references
  if (pruneInterval.unref) pruneInterval.unref();

  return function rateLimitMiddleware(req, res, next) {
    // Use IP as the client key (works behind reverse proxies when trust proxy is set)
    const key = req.ip || req.connection?.remoteAddress || 'unknown';
    const now = Date.now();
    const cutoff = now - windowMs;

    let timestamps = clients.get(key) || [];
    // Remove expired entries
    timestamps = timestamps.filter(t => t > cutoff);

    if (timestamps.length >= max) {
      const retryAfter = Math.ceil((timestamps[0] + windowMs - now) / 1000);
      res.set('Retry-After', String(retryAfter));
      return res.status(429).json({
        error: 'Too many requests',
        retryAfterSeconds: retryAfter,
      });
    }

    timestamps.push(now);
    clients.set(key, timestamps);
    next();
  };
}

module.exports = rateLimit;
