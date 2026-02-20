/**
 * Backend Winston Logger
 * 
 * Provides structured logging for the Lego Loco backend server.
 * Uses Winston with console + daily rotate file transports.
 */

const winston = require('winston');
const path = require('path');

// Attempt to load daily rotate - not critical if missing
let DailyRotateFile;
try {
  DailyRotateFile = require('winston-daily-rotate-file');
} catch (e) {
  // Optional dependency
}

const LOG_DIR = path.join(__dirname, '..', 'logs');

const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
  winston.format.errors({ stack: true }),
  winston.format.printf(({ timestamp, level, message, ...meta }) => {
    const metaStr = Object.keys(meta).length ? ' ' + JSON.stringify(meta) : '';
    return `[${timestamp}] [${level.toUpperCase()}] ${message}${metaStr}`;
  })
);

const transports = [
  new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      logFormat
    ),
  }),
];

// Add file transport if daily rotate is available
if (DailyRotateFile) {
  transports.push(
    new DailyRotateFile({
      dirname: LOG_DIR,
      filename: 'backend-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      maxSize: '20m',
      maxFiles: '14d',
      format: logFormat,
    })
  );
}

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  transports,
});

module.exports = logger;
