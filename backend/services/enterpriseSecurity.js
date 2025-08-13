const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');

/**
 * Enterprise Security Middleware
 * Provides comprehensive security features for production deployment
 */
class EnterpriseSecurity {
    constructor(config = {}) {
        this.config = {
            rateLimiting: {
                windowMs: config.rateLimitWindow || 15 * 60 * 1000, // 15 minutes
                max: config.rateLimitMax || 100, // limit each IP to 100 requests per windowMs
                standardHeaders: true,
                legacyHeaders: false,
                message: {
                    error: 'Too many requests from this IP, please try again later.',
                    retryAfter: '15 minutes'
                }
            },
            auth: {
                enabled: config.authEnabled || process.env.NODE_ENV === 'production',
                apiKeys: config.apiKeys || (process.env.API_KEYS ? process.env.API_KEYS.split(',') : []),
                jwtSecret: config.jwtSecret || process.env.JWT_SECRET || 'default-secret-change-in-production',
                tokenExpiry: config.tokenExpiry || '1h'
            },
            validation: {
                enabled: config.validationEnabled !== false,
                maxRequestSize: config.maxRequestSize || '10mb',
                allowedOrigins: config.allowedOrigins || ['http://localhost:3000', 'http://localhost:3002']
            },
            audit: {
                enabled: config.auditEnabled !== false,
                logFile: config.auditLogFile || './logs/security-audit.log',
                logSensitiveData: config.logSensitiveData || false
            }
        };

        this.auditLogger = this.initializeAuditLogger();
        this.securityMetrics = {
            blockedRequests: 0,
            failedAuthentications: 0,
            suspiciousActivities: 0,
            rateLimitViolations: 0
        };
    }

    /**
     * Initialize audit logging
     */
    initializeAuditLogger() {
        const fs = require('fs');
        const path = require('path');

        if (!this.config.audit.enabled) {
            return null;
        }

        const logDir = path.dirname(this.config.audit.logFile);
        if (!fs.existsSync(logDir)) {
            fs.mkdirSync(logDir, { recursive: true });
        }

        return (event, details = {}) => {
            const auditEntry = {
                timestamp: new Date().toISOString(),
                event,
                ...details,
                service: 'lego-loco-cluster'
            };

            const logLine = JSON.stringify(auditEntry) + '\n';
            
            try {
                fs.appendFileSync(this.config.audit.logFile, logLine);
            } catch (error) {
                console.error('Failed to write audit log:', error.message);
            }
        };
    }

    /**
     * Helmet configuration for security headers
     */
    getHelmetConfig() {
        return helmet({
            contentSecurityPolicy: {
                directives: {
                    defaultSrc: ["'self'"],
                    styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
                    fontSrc: ["'self'", "https://fonts.gstatic.com"],
                    imgSrc: ["'self'", "data:", "https:"],
                    scriptSrc: ["'self'"],
                    connectSrc: ["'self'", "ws:", "wss:"],
                    frameSrc: ["'none'"],
                    objectSrc: ["'none'"],
                    upgradeInsecureRequests: process.env.NODE_ENV === 'production' ? [] : null
                }
            },
            hsts: {
                maxAge: 31536000,
                includeSubDomains: true,
                preload: true
            },
            noSniff: true,
            frameguard: { action: 'deny' },
            xssFilter: true,
            referrerPolicy: { policy: "same-origin" }
        });
    }

    /**
     * Rate limiting configuration
     */
    getRateLimitConfig() {
        return rateLimit({
            ...this.config.rateLimiting,
            handler: (req, res) => {
                this.securityMetrics.rateLimitViolations++;
                
                if (this.auditLogger) {
                    this.auditLogger('RATE_LIMIT_EXCEEDED', {
                        ip: req.ip,
                        userAgent: req.get('User-Agent'),
                        path: req.path,
                        method: req.method
                    });
                }

                res.status(429).json(this.config.rateLimiting.message);
            }
        });
    }

    /**
     * API Key authentication middleware
     */
    apiKeyAuth() {
        return (req, res, next) => {
            if (!this.config.auth.enabled) {
                return next();
            }

            const apiKey = req.header('X-API-Key') || req.query.apiKey;
            
            if (!apiKey) {
                this.securityMetrics.failedAuthentications++;
                
                if (this.auditLogger) {
                    this.auditLogger('AUTH_MISSING_API_KEY', {
                        ip: req.ip,
                        userAgent: req.get('User-Agent'),
                        path: req.path
                    });
                }

                return res.status(401).json({ 
                    error: 'API key required',
                    code: 'MISSING_API_KEY'
                });
            }

            if (!this.config.auth.apiKeys.includes(apiKey)) {
                this.securityMetrics.failedAuthentications++;
                
                if (this.auditLogger) {
                    this.auditLogger('AUTH_INVALID_API_KEY', {
                        ip: req.ip,
                        userAgent: req.get('User-Agent'),
                        path: req.path,
                        apiKeyHash: crypto.createHash('sha256').update(apiKey).digest('hex').substring(0, 8)
                    });
                }

                return res.status(401).json({ 
                    error: 'Invalid API key',
                    code: 'INVALID_API_KEY'
                });
            }

            if (this.auditLogger) {
                this.auditLogger('AUTH_SUCCESS', {
                    ip: req.ip,
                    path: req.path,
                    method: req.method
                });
            }

            next();
        };
    }

    /**
     * Input validation and sanitization
     */
    inputValidation() {
        return (req, res, next) => {
            if (!this.config.validation.enabled) {
                return next();
            }

            // Check for suspicious patterns
            const suspiciousPatterns = [
                /<script[^>]*>.*?<\/script>/gi,
                /javascript:/gi,
                /on\w+\s*=/gi,
                /\b(union|select|insert|delete|drop|create|alter)\b/gi,
                /\.\.\/|\.\.\\|~\//gi,
                /<iframe[^>]*>.*?<\/iframe>/gi
            ];

            const checkForSuspiciousContent = (obj, path = '') => {
                if (typeof obj === 'string') {
                    for (const pattern of suspiciousPatterns) {
                        if (pattern.test(obj)) {
                            this.securityMetrics.suspiciousActivities++;
                            
                            if (this.auditLogger) {
                                this.auditLogger('SUSPICIOUS_INPUT_DETECTED', {
                                    ip: req.ip,
                                    userAgent: req.get('User-Agent'),
                                    path: req.path,
                                    method: req.method,
                                    field: path,
                                    pattern: pattern.toString(),
                                    content: this.config.audit.logSensitiveData ? obj : '[REDACTED]'
                                });
                            }

                            return true;
                        }
                    }
                } else if (obj && typeof obj === 'object') {
                    for (const [key, value] of Object.entries(obj)) {
                        if (checkForSuspiciousContent(value, path ? `${path}.${key}` : key)) {
                            return true;
                        }
                    }
                }
                return false;
            };

            // Check query parameters
            if (checkForSuspiciousContent(req.query, 'query')) {
                return res.status(400).json({
                    error: 'Invalid input detected',
                    code: 'SUSPICIOUS_INPUT'
                });
            }

            // Check request body
            if (req.body && checkForSuspiciousContent(req.body, 'body')) {
                return res.status(400).json({
                    error: 'Invalid input detected',
                    code: 'SUSPICIOUS_INPUT'
                });
            }

            next();
        };
    }

    /**
     * CORS configuration
     */
    corsMiddleware() {
        return (req, res, next) => {
            const origin = req.headers.origin;
            
            if (this.config.validation.allowedOrigins.includes(origin) || !origin) {
                res.header('Access-Control-Allow-Origin', origin || '*');
            }
            
            res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
            res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, X-API-Key');
            res.header('Access-Control-Allow-Credentials', 'true');
            res.header('Access-Control-Max-Age', '86400'); // 24 hours

            if (req.method === 'OPTIONS') {
                res.sendStatus(200);
            } else {
                next();
            }
        };
    }

    /**
     * Request logging middleware
     */
    requestLogger() {
        return (req, res, next) => {
            const startTime = Date.now();
            
            // Log request
            if (this.auditLogger) {
                this.auditLogger('REQUEST_START', {
                    ip: req.ip,
                    method: req.method,
                    path: req.path,
                    userAgent: req.get('User-Agent'),
                    requestId: req.headers['x-request-id'] || crypto.randomUUID()
                });
            }

            // Override res.end to log response
            const originalEnd = res.end;
            const self = this;
            res.end = function(...args) {
                const duration = Date.now() - startTime;
                
                if (self.auditLogger) {
                    self.auditLogger('REQUEST_END', {
                        ip: req.ip,
                        method: req.method,
                        path: req.path,
                        statusCode: res.statusCode,
                        duration,
                        requestId: req.headers['x-request-id']
                    });
                }

                originalEnd.apply(this, args);
            };

            next();
        };
    }

    /**
     * Error handling middleware
     */
    errorHandler() {
        return (error, req, res, next) => {
            const errorId = crypto.randomUUID();
            
            // Log error
            console.error(`[ERROR ${errorId}]`, error);
            
            if (this.auditLogger) {
                this.auditLogger('ERROR', {
                    errorId,
                    ip: req.ip,
                    method: req.method,
                    path: req.path,
                    error: error.message,
                    stack: error.stack
                });
            }

            // Don't leak sensitive information in production
            const isDevelopment = process.env.NODE_ENV === 'development';
            
            res.status(error.status || 500).json({
                error: isDevelopment ? error.message : 'Internal server error',
                code: error.code || 'INTERNAL_ERROR',
                errorId: isDevelopment ? errorId : undefined,
                stack: isDevelopment ? error.stack : undefined
            });
        };
    }

    /**
     * Security health check endpoint
     */
    securityHealthCheck() {
        return (req, res) => {
            const health = {
                timestamp: new Date().toISOString(),
                security: {
                    status: 'healthy',
                    features: {
                        rateLimiting: true,
                        authentication: this.config.auth.enabled,
                        inputValidation: this.config.validation.enabled,
                        auditLogging: this.config.audit.enabled,
                        securityHeaders: true
                    },
                    metrics: this.securityMetrics,
                    configuration: {
                        rateLimitWindow: this.config.rateLimiting.windowMs,
                        rateLimitMax: this.config.rateLimiting.max,
                        authEnabled: this.config.auth.enabled,
                        validationEnabled: this.config.validation.enabled
                    }
                }
            };

            res.json(health);
        };
    }

    /**
     * Get all security middleware
     */
    getAllMiddleware() {
        return [
            this.getHelmetConfig(),
            this.corsMiddleware(),
            this.getRateLimitConfig(),
            this.requestLogger(),
            this.inputValidation()
        ];
    }

    /**
     * Get security metrics
     */
    getMetrics() {
        return {
            ...this.securityMetrics,
            timestamp: new Date().toISOString()
        };
    }
}

module.exports = EnterpriseSecurity;