/**
 * Frontend Logger Utility
 * Mirrors backend Winston logger format for consistency.
 * Always active, defaults to 'info' level.
 */

class FrontendLogger {
  constructor(component) {
    this.component = component;
    // Default to 'info', allow override via env var
    // Levels: debug (0), info (1), warn (2), error (3)
    this.logLevel = import.meta.env.VITE_LOG_LEVEL || 'info';
    this.levels = { debug: 0, info: 1, warn: 2, error: 3 };
  }

  _shouldLog(level) {
    const currentLevelScore = this.levels[this.logLevel] || 1; // Default to info if invalid
    const messageLevelScore = this.levels[level] || 1;
    return messageLevelScore >= currentLevelScore;
  }

  _log(level, message, context = {}) {
    if (!this._shouldLog(level)) return;

    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level,
      component: this.component,
      message,
      ...context
    };

    // Console output with color
    const colors = {
      debug: 'color: #36D399',   // cyan-ish
      info: 'color: #3ABFF8',    // blue
      warn: 'color: #FBBD23',    // yellow
      error: 'color: #F87272',   // red
    };

    // Format: [TIMESTAMP] [LEVEL] [COMPONENT]: Message {context}
    console.log(
      `%c[${timestamp}] [${level.toUpperCase()}] [${this.component}]:`,
      `${colors[level] || 'color: inherit'}; font-weight: bold`,
      message,
      Object.keys(context).length ? context : ''
    );

    // Emit event for metrics collection or backend aggregation
    // This allows the metrics collector to subscribe to log events without direct coupling
    window.dispatchEvent(new CustomEvent('frontendLog', { detail: logEntry }));
  }

  debug(msg, ctx) { this._log('debug', msg, ctx); }
  info(msg, ctx) { this._log('info', msg, ctx); }
  warn(msg, ctx) { this._log('warn', msg, ctx); }
  error(msg, ctx) { this._log('error', msg, ctx); }
}

export function createLogger(component) {
  return new FrontendLogger(component);
}