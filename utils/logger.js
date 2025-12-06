const winston = require('winston');
const DailyRotateFile = require('winston-daily-rotate-file');
const path = require('path');

// Create logs directory if it doesn't exist
const logsDir = path.join(__dirname, '../logs');
require('fs').mkdirSync(logsDir, { recursive: true });

// Get log level from environment variable, default to 'info'
const logLevel = process.env.LOG_LEVEL || 'info';

// Custom format for console output
const consoleFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.colorize(),
  winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
    let logMessage = `${timestamp} [${level}]`;

    // Add service name if present
    if (service) {
      logMessage += ` [${service}]`;
    }

    logMessage += `: ${message}`;

    // Add metadata if present
    const metaKeys = Object.keys(meta);
    if (metaKeys.length > 0) {
      logMessage += ` ${JSON.stringify(meta)}`;
    }

    return logMessage;
  })
);

// Custom format for file output
const fileFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.json()
);

/**
 * Create a logger instance with specified service name
 * @param {string} serviceName - Name of the service/component using the logger
 * @returns {winston.Logger} Configured Winston logger instance
 */
function createLogger(serviceName = 'lego-loco-app') {
  // Daily rotate file transport for general logs
  const dailyRotateTransport = new DailyRotateFile({
    filename: path.join(logsDir, 'application-%DATE%.log'),
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: '14d',
    format: fileFormat,
    level: logLevel
  });

  // Daily rotate file transport for error logs only
  const errorRotateTransport = new DailyRotateFile({
    filename: path.join(logsDir, 'error-%DATE%.log'),
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: '30d',
    format: fileFormat,
    level: 'error'
  });

  // Create the logger
  const logger = winston.createLogger({
    level: logLevel,
    defaultMeta: { service: serviceName },
    transports: [
      dailyRotateTransport,
      errorRotateTransport
    ]
  });

  // Always add console transport for Kubernetes/Container environments
  logger.add(new winston.transports.Console({
    format: consoleFormat,
    level: logLevel
  }));

  return logger;
}

/**
 * Create a simple console-only logger for testing environments
 * @param {string} serviceName - Name of the service/component using the logger
 * @returns {winston.Logger} Console-only Winston logger instance
 */
function createTestLogger(serviceName = 'lego-loco-test') {
  const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    defaultMeta: { service: serviceName },
    transports: [
      new winston.transports.Console({
        format: consoleFormat,
        level: process.env.LOG_LEVEL || 'info'
      })
    ]
  });

  return logger;
}

// Export the default backend logger for backward compatibility
const defaultLogger = createLogger('lego-loco-backend');

module.exports = {
  createLogger,
  createTestLogger,
  logger: defaultLogger,
  // Export default logger methods for backward compatibility
  info: defaultLogger.info.bind(defaultLogger),
  warn: defaultLogger.warn.bind(defaultLogger),
  error: defaultLogger.error.bind(defaultLogger),
  debug: defaultLogger.debug.bind(defaultLogger)
};