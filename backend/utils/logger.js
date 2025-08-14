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
    filename: path.join(logsDir, `${serviceName}-%DATE%.log`),
    datePattern: 'YYYY-MM-DD',
    zippedArchive: true,
    maxSize: '20m',
    maxFiles: '14d',
    format: fileFormat
  });

  // Daily rotate file transport for error logs
  const errorRotateTransport = new DailyRotateFile({
    filename: path.join(logsDir, `${serviceName}-error-%DATE%.log`),
    datePattern: 'YYYY-MM-DD',
    zippedArchive: true,
    maxSize: '20m',
    maxFiles: '30d',
    level: 'error',
    format: fileFormat
  });

  const logger = winston.createLogger({
    level: logLevel,
    defaultMeta: { service: serviceName },
    transports: [
      dailyRotateTransport,
      errorRotateTransport
    ],
    exceptionHandlers: [
      new winston.transports.File({ 
        filename: path.join(logsDir, `${serviceName}-exceptions.log`),
        format: fileFormat
      })
    ],
    rejectionHandlers: [
      new winston.transports.File({ 
        filename: path.join(logsDir, `${serviceName}-rejections.log`),
        format: fileFormat
      })
    ]
  });

  // Add console transport in development or when explicitly requested
  if (process.env.NODE_ENV !== 'production' || process.env.FORCE_CONSOLE_LOGGING === 'true') {
    logger.add(new winston.transports.Console({
      format: consoleFormat
    }));
  }

  return logger;
}

// Create default logger instance
const defaultLogger = createLogger('backend');

module.exports = {
  createLogger,
  logger: defaultLogger,
  // Export common log methods for convenience
  info: defaultLogger.info.bind(defaultLogger),
  error: defaultLogger.error.bind(defaultLogger),
  warn: defaultLogger.warn.bind(defaultLogger),
  debug: defaultLogger.debug.bind(defaultLogger)
};
