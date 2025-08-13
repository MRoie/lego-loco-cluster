/**
 * Frontend Browser Logger
 * Provides structured logging for React components and browser-based code
 * Compatible with the backend Winston logging structure
 */

// Log levels with numeric values for filtering
const LOG_LEVELS = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3
};

// Get log level from environment or default to 'info'
const getLogLevel = () => {
  // In development, allow debug logs
  if (import.meta.env?.DEV) {
    return import.meta.env?.VITE_LOG_LEVEL || 'debug';
  }
  // In production, default to 'warn' to reduce noise
  return import.meta.env?.VITE_LOG_LEVEL || 'warn';
};

const currentLogLevel = getLogLevel();
const currentLogLevelNum = LOG_LEVELS[currentLogLevel] || LOG_LEVELS.info;

/**
 * Check if a message should be logged based on current log level
 * @param {string} level - Log level to check
 * @returns {boolean} Whether the message should be logged
 */
const shouldLog = (level) => {
  return LOG_LEVELS[level] >= currentLogLevelNum;
};

/**
 * Format a log message with timestamp and context
 * @param {string} level - Log level
 * @param {string} message - Log message
 * @param {object} context - Additional context
 * @param {string} component - Component name
 * @returns {object} Formatted log object
 */
const formatLogMessage = (level, message, context = {}, component = 'frontend') => {
  return {
    timestamp: new Date().toISOString(),
    level,
    message,
    component,
    service: 'lego-loco-frontend',
    ...context
  };
};

/**
 * Send log to console with appropriate method
 * @param {string} level - Log level
 * @param {object} logObj - Formatted log object
 */
const outputLog = (level, logObj) => {
  const consoleMethod = level === 'debug' ? 'log' : level;
  
  if (console[consoleMethod]) {
    // In development, show structured logs
    if (import.meta.env?.DEV) {
      console[consoleMethod](`[${logObj.timestamp}] [${level.toUpperCase()}] [${logObj.component}]: ${logObj.message}`, logObj);
    } else {
      // In production, simpler format
      console[consoleMethod](`[${level.toUpperCase()}] ${logObj.message}`, logObj);
    }
  }
};

/**
 * Create a logger for a specific component
 * @param {string} componentName - Name of the component using the logger
 * @returns {object} Logger instance with debug, info, warn, error methods
 */
export function createLogger(componentName = 'unknown-component') {
  const log = (level, message, context = {}) => {
    if (!shouldLog(level)) return;
    
    const logObj = formatLogMessage(level, message, context, componentName);
    outputLog(level, logObj);
    
    // In development, also send to parent window if in iframe for debugging
    if (import.meta.env?.DEV && window.parent !== window) {
      try {
        window.parent.postMessage({
          type: 'LOG',
          log: logObj
        }, '*');
      } catch (e) {
        // Ignore if parent window access is blocked
      }
    }
  };

  return {
    debug: (message, context = {}) => log('debug', message, context),
    info: (message, context = {}) => log('info', message, context),
    warn: (message, context = {}) => log('warn', message, context),
    error: (message, context = {}) => log('error', message, context),
    
    // Convenience methods with context
    debugWithContext: (message, context = {}) => log('debug', message, context),
    infoWithContext: (message, context = {}) => log('info', message, context),
    warnWithContext: (message, context = {}) => log('warn', message, context),
    errorWithContext: (message, context = {}) => log('error', message, context)
  };
}

// Default logger for general frontend use
const defaultLogger = createLogger('frontend');

export default defaultLogger;

// Export individual methods for convenience
export const { debug, info, warn, error } = defaultLogger;