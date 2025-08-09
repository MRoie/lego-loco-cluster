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
  winston.format.printf(({ timestamp, level, message, ...meta }) => {
    let logMessage = `${timestamp} [${level}]: ${message}`;
    
    // Add metadata if present
    if (Object.keys(meta).length > 0) {
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
  defaultMeta: { service: 'lego-loco-backend' },
  transports: [
    dailyRotateTransport,
    errorRotateTransport
  ]
});

// Add console transport for non-production environments
if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: consoleFormat,
    level: logLevel
  }));
}

// Add convenience methods for common use cases
logger.logWithContext = (level, message, context = {}) => {
  logger.log(level, message, context);
};

logger.info = (message, context = {}) => {
  logger.logWithContext('info', message, context);
};

logger.warn = (message, context = {}) => {
  logger.logWithContext('warn', message, context);
};

logger.error = (message, context = {}) => {
  logger.logWithContext('error', message, context);
};

logger.debug = (message, context = {}) => {
  logger.logWithContext('debug', message, context);
};

module.exports = logger;