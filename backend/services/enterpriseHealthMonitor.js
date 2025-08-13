const fs = require('fs');
const path = require('path');
const EventEmitter = require('events');
const fetch = require('node-fetch');

/**
 * Enterprise-Grade Health Monitoring Service
 * Provides comprehensive monitoring, alerting, and recovery capabilities
 */
class EnterpriseHealthMonitor extends EventEmitter {
    constructor(instanceManager, config = {}) {
        super();
        this.instanceManager = instanceManager;
        this.config = {
            checkInterval: config.checkInterval || 30000, // 30 seconds
            healthEndpoint: config.healthEndpoint || '/health',
            alertThresholds: {
                cpu: config.cpuThreshold || 80,
                memory: config.memoryThreshold || 85,
                frameRate: config.frameRateThreshold || 10,
                errorRate: config.errorRateThreshold || 5,
                responseTime: config.responseTimeThreshold || 5000
            },
            circuitBreaker: {
                threshold: config.circuitBreakerThreshold || 5,
                timeout: config.circuitBreakerTimeout || 60000,
                retryTimeout: config.retryTimeout || 30000
            },
            alerts: {
                webhook: config.webhookUrl || process.env.ALERT_WEBHOOK_URL,
                email: config.alertEmail || process.env.ALERT_EMAIL,
                cooldown: config.alertCooldown || 300000 // 5 minutes
            },
            recovery: {
                autoRestart: config.autoRestart || true,
                maxRestartAttempts: config.maxRestartAttempts || 3,
                restartDelay: config.restartDelay || 10000
            }
        };
        
        this.state = {
            lastAlertTime: {},
            circuitBreakers: {},
            consecutiveFailures: {},
            healthHistory: {},
            metrics: {
                totalChecks: 0,
                successfulChecks: 0,
                failedChecks: 0,
                avgResponseTime: 0,
                uptime: Date.now()
            }
        };
        
        this.isRunning = false;
        this.checkTimer = null;
        this.logFile = path.join(process.cwd(), 'logs', 'enterprise-health.log');
        
        // Ensure log directory exists
        const logDir = path.dirname(this.logFile);
        if (!fs.existsSync(logDir)) {
            fs.mkdirSync(logDir, { recursive: true });
        }
        
        this.log('info', 'Enterprise Health Monitor initialized', { config: this.config });
    }
    
    /**
     * Structured logging with enterprise features
     */
    log(level, message, meta = {}) {
        const timestamp = new Date().toISOString();
        const logEntry = {
            timestamp,
            level: level.toUpperCase(),
            message,
            service: 'enterprise-health-monitor',
            ...meta
        };
        
        const logLine = JSON.stringify(logEntry) + '\n';
        
        // Console output
        console.log(`[${timestamp}] [${level.toUpperCase()}] ${message}`, meta);
        
        // File logging
        try {
            fs.appendFileSync(this.logFile, logLine);
        } catch (error) {
            console.error('Failed to write to log file:', error.message);
        }
        
        // Emit log event for external systems
        this.emit('log', logEntry);
    }
    
    /**
     * Alert mechanism with cooldown and multiple channels
     */
    async sendAlert(severity, message, instanceId = 'system', meta = {}) {
        const now = Date.now();
        const alertKey = `${instanceId}-${severity}`;
        
        // Check cooldown
        if (this.state.lastAlertTime[alertKey] && 
            (now - this.state.lastAlertTime[alertKey]) < this.config.alerts.cooldown) {
            this.log('debug', 'Alert skipped due to cooldown', { alertKey, severity, message });
            return;
        }
        
        this.state.lastAlertTime[alertKey] = now;
        
        const alert = {
            id: `alert_${now}_${Math.random().toString(36).substr(2, 9)}`,
            timestamp: new Date().toISOString(),
            severity,
            message,
            instanceId,
            service: 'lego-loco-cluster',
            meta
        };
        
        this.log('warn', `ALERT [${severity}]: ${message}`, alert);
        
        // Webhook alert
        if (this.config.alerts.webhook) {
            try {
                const response = await fetch(this.config.alerts.webhook, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(alert),
                    timeout: 5000
                });
                
                if (!response.ok) {
                    throw new Error(`Webhook returned ${response.status}`);
                }
                
                this.log('info', 'Alert sent via webhook', { alertId: alert.id });
            } catch (error) {
                this.log('error', 'Failed to send webhook alert', { error: error.message, alertId: alert.id });
            }
        }
        
        // Emit alert event
        this.emit('alert', alert);
    }
    
    /**
     * Circuit breaker implementation
     */
    isCircuitBreakerOpen(instanceId) {
        const breaker = this.state.circuitBreakers[instanceId];
        if (!breaker) return false;
        
        if (breaker.state === 'open') {
            // Check if timeout has passed
            if (Date.now() - breaker.openedAt > this.config.circuitBreaker.timeout) {
                breaker.state = 'half-open';
                this.log('info', 'Circuit breaker moved to half-open', { instanceId });
            }
            return breaker.state === 'open';
        }
        
        return false;
    }
    
    /**
     * Update circuit breaker state
     */
    updateCircuitBreaker(instanceId, success) {
        if (!this.state.circuitBreakers[instanceId]) {
            this.state.circuitBreakers[instanceId] = {
                failures: 0,
                state: 'closed',
                openedAt: null
            };
        }
        
        const breaker = this.state.circuitBreakers[instanceId];
        
        if (success) {
            breaker.failures = 0;
            if (breaker.state === 'half-open') {
                breaker.state = 'closed';
                this.log('info', 'Circuit breaker closed', { instanceId });
            }
        } else {
            breaker.failures++;
            
            if (breaker.failures >= this.config.circuitBreaker.threshold && breaker.state === 'closed') {
                breaker.state = 'open';
                breaker.openedAt = Date.now();
                this.log('error', 'Circuit breaker opened', { 
                    instanceId, 
                    failures: breaker.failures,
                    threshold: this.config.circuitBreaker.threshold
                });
                this.sendAlert('CRITICAL', `Circuit breaker opened for instance ${instanceId}`, instanceId);
            }
        }
    }
    
    /**
     * Retry mechanism with exponential backoff
     */
    async retryWithBackoff(fn, maxAttempts = 3, baseDelay = 1000) {
        let attempt = 0;
        let delay = baseDelay;
        
        while (attempt < maxAttempts) {
            try {
                return await fn();
            } catch (error) {
                attempt++;
                if (attempt >= maxAttempts) {
                    throw error;
                }
                
                this.log('warn', `Retry attempt ${attempt}/${maxAttempts} failed, retrying in ${delay}ms`, { 
                    error: error.message 
                });
                
                await new Promise(resolve => setTimeout(resolve, delay));
                delay *= 2; // Exponential backoff
            }
        }
    }
    
    /**
     * Enhanced health check for a single instance
     */
    async checkInstanceHealth(instance) {
        const startTime = Date.now();
        const instanceId = instance.id || 'unknown';
        
        // Skip if circuit breaker is open
        if (this.isCircuitBreakerOpen(instanceId)) {
            this.log('debug', 'Skipping health check - circuit breaker open', { instanceId });
            return { status: 'circuit_breaker_open', instanceId };
        }
        
        try {
            const healthUrl = `http://${instance.host}:${instance.healthPort || 8080}${this.config.healthEndpoint}`;
            
            const healthCheck = async () => {
                const controller = new AbortController();
                const timeout = setTimeout(() => controller.abort(), this.config.alertThresholds.responseTime);
                
                try {
                    const response = await fetch(healthUrl, {
                        method: 'GET',
                        signal: controller.signal,
                        headers: {
                            'Accept': 'application/json',
                            'User-Agent': 'EnterpriseHealthMonitor/1.0'
                        }
                    });
                    
                    clearTimeout(timeout);
                    
                    if (!response.ok) {
                        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                    }
                    
                    const healthData = await response.json();
                    const responseTime = Date.now() - startTime;
                    
                    // Validate health data structure
                    if (!healthData || typeof healthData !== 'object') {
                        throw new Error('Invalid health data format');
                    }
                    
                    // Analyze health metrics
                    const analysis = this.analyzeHealthData(healthData, instance);
                    
                    this.updateCircuitBreaker(instanceId, true);
                    
                    return {
                        status: 'healthy',
                        instanceId,
                        responseTime,
                        data: healthData,
                        analysis,
                        timestamp: new Date().toISOString()
                    };
                    
                } finally {
                    clearTimeout(timeout);
                }
            };
            
            // Execute with retry logic
            const result = await this.retryWithBackoff(healthCheck, 3, 1000);
            
            // Update metrics
            this.state.metrics.successfulChecks++;
            this.updateMetrics(instanceId, result);
            
            return result;
            
        } catch (error) {
            const responseTime = Date.now() - startTime;
            
            this.updateCircuitBreaker(instanceId, false);
            this.state.metrics.failedChecks++;
            
            this.log('error', 'Health check failed', { 
                instanceId, 
                error: error.message, 
                responseTime 
            });
            
            // Alert on health check failure
            await this.sendAlert('WARNING', `Health check failed for instance ${instanceId}: ${error.message}`, instanceId);
            
            return {
                status: 'unhealthy',
                instanceId,
                error: error.message,
                responseTime,
                timestamp: new Date().toISOString()
            };
        }
    }
    
    /**
     * Analyze health data for enterprise insights
     */
    analyzeHealthData(healthData, instance) {
        const analysis = {
            score: 100,
            issues: [],
            recommendations: [],
            slaStatus: 'compliant'
        };
        
        // QEMU process analysis
        if (!healthData.qemu_healthy) {
            analysis.score -= 30;
            analysis.issues.push('qemu_not_running');
            analysis.recommendations.push('Restart QEMU emulator process');
        }
        
        // Performance analysis
        if (healthData.performance) {
            const perf = healthData.performance;
            
            if (parseFloat(perf.cpu_usage) > this.config.alertThresholds.cpu) {
                analysis.score -= 15;
                analysis.issues.push('high_cpu_usage');
                analysis.recommendations.push('Investigate CPU usage and consider resource scaling');
            }
            
            if (parseFloat(perf.memory_usage) > this.config.alertThresholds.memory) {
                analysis.score -= 15;
                analysis.issues.push('high_memory_usage');
                analysis.recommendations.push('Monitor memory leaks and consider memory optimization');
            }
        }
        
        // Video system analysis
        if (healthData.video) {
            const video = healthData.video;
            
            if (!video.vnc_available) {
                analysis.score -= 20;
                analysis.issues.push('vnc_unavailable');
                analysis.recommendations.push('Check VNC server configuration and network connectivity');
            }
            
            if (video.estimated_frame_rate && video.estimated_frame_rate < this.config.alertThresholds.frameRate) {
                analysis.score -= 10;
                analysis.issues.push('low_frame_rate');
                analysis.recommendations.push('Investigate graphics performance and display settings');
            }
        }
        
        // Audio system analysis
        if (healthData.audio && !healthData.audio.pulse_running) {
            analysis.score -= 15;
            analysis.issues.push('audio_system_down');
            analysis.recommendations.push('Restart PulseAudio service');
        }
        
        // Network analysis
        if (healthData.network) {
            const net = healthData.network;
            
            if (!net.bridge_up || !net.tap_up) {
                analysis.score -= 10;
                analysis.issues.push('network_interface_down');
                analysis.recommendations.push('Check network bridge and TAP interface configuration');
            }
            
            // Error rate analysis
            if (net.tx_error_rate && parseFloat(net.tx_error_rate) > this.config.alertThresholds.errorRate) {
                analysis.score -= 5;
                analysis.issues.push('high_network_errors');
                analysis.recommendations.push('Investigate network hardware and driver issues');
            }
        }
        
        // SLA status determination
        if (analysis.score < 50) {
            analysis.slaStatus = 'critical';
        } else if (analysis.score < 80) {
            analysis.slaStatus = 'degraded';
        } else if (analysis.score < 95) {
            analysis.slaStatus = 'warning';
        }
        
        return analysis;
    }
    
    /**
     * Update performance metrics
     */
    updateMetrics(instanceId, result) {
        if (!this.state.healthHistory[instanceId]) {
            this.state.healthHistory[instanceId] = [];
        }
        
        const history = this.state.healthHistory[instanceId];
        history.push({
            timestamp: Date.now(),
            status: result.status,
            responseTime: result.responseTime || 0,
            score: result.analysis ? result.analysis.score : 0
        });
        
        // Keep only last 100 entries per instance
        if (history.length > 100) {
            history.splice(0, history.length - 100);
        }
        
        // Update global metrics
        this.state.metrics.totalChecks++;
        
        const totalResponseTimes = Object.values(this.state.healthHistory)
            .flat()
            .map(h => h.responseTime)
            .filter(rt => rt > 0);
            
        if (totalResponseTimes.length > 0) {
            this.state.metrics.avgResponseTime = totalResponseTimes.reduce((a, b) => a + b, 0) / totalResponseTimes.length;
        }
    }
    
    /**
     * Auto-recovery mechanism
     */
    async attemptRecovery(instance, healthResult) {
        if (!this.config.recovery.autoRestart) {
            return false;
        }
        
        const instanceId = instance.id || 'unknown';
        const consecutiveFailures = this.state.consecutiveFailures[instanceId] || 0;
        
        if (consecutiveFailures >= this.config.recovery.maxRestartAttempts) {
            this.log('error', 'Max restart attempts reached', { instanceId, attempts: consecutiveFailures });
            await this.sendAlert('CRITICAL', `Max restart attempts reached for instance ${instanceId}`, instanceId);
            return false;
        }
        
        this.log('info', 'Attempting auto-recovery', { instanceId, attempt: consecutiveFailures + 1 });
        
        try {
            // Simulate restart command (would integrate with actual container orchestration)
            await this.sendAlert('INFO', `Attempting auto-recovery for instance ${instanceId}`, instanceId);
            
            // Wait for restart delay
            await new Promise(resolve => setTimeout(resolve, this.config.recovery.restartDelay));
            
            this.state.consecutiveFailures[instanceId] = consecutiveFailures + 1;
            
            this.log('info', 'Auto-recovery initiated', { instanceId });
            return true;
            
        } catch (error) {
            this.log('error', 'Auto-recovery failed', { instanceId, error: error.message });
            await this.sendAlert('ERROR', `Auto-recovery failed for instance ${instanceId}: ${error.message}`, instanceId);
            return false;
        }
    }
    
    /**
     * Main health monitoring loop
     */
    async performHealthChecks() {
        this.log('debug', 'Starting health check cycle');
        
        try {
            const instances = await this.instanceManager.getProvisionedInstances();
            const healthResults = [];
            
            // Parallel health checks with error isolation
            const checkPromises = instances.map(async (instance) => {
                try {
                    const result = await this.checkInstanceHealth(instance);
                    
                    // Auto-recovery for failed instances
                    if (result.status === 'unhealthy') {
                        await this.attemptRecovery(instance, result);
                    } else {
                        // Reset consecutive failures on success
                        this.state.consecutiveFailures[instance.id] = 0;
                    }
                    
                    return result;
                } catch (error) {
                    this.log('error', 'Health check error', { 
                        instanceId: instance.id, 
                        error: error.message 
                    });
                    return {
                        status: 'error',
                        instanceId: instance.id,
                        error: error.message,
                        timestamp: new Date().toISOString()
                    };
                }
            });
            
            const results = await Promise.allSettled(checkPromises);
            
            // Process results
            results.forEach((result, index) => {
                if (result.status === 'fulfilled') {
                    healthResults.push(result.value);
                } else {
                    const instance = instances[index];
                    this.log('error', 'Health check promise rejected', { 
                        instanceId: instance?.id, 
                        error: result.reason?.message 
                    });
                    healthResults.push({
                        status: 'error',
                        instanceId: instance?.id,
                        error: result.reason?.message,
                        timestamp: new Date().toISOString()
                    });
                }
            });
            
            // Emit health check results
            this.emit('healthCheck', {
                timestamp: new Date().toISOString(),
                totalInstances: instances.length,
                results: healthResults,
                metrics: this.state.metrics
            });
            
            this.log('info', 'Health check cycle completed', { 
                totalInstances: instances.length,
                healthyCount: healthResults.filter(r => r.status === 'healthy').length,
                unhealthyCount: healthResults.filter(r => r.status === 'unhealthy').length
            });
            
        } catch (error) {
            this.log('error', 'Health check cycle failed', { error: error.message });
            await this.sendAlert('ERROR', `Health monitoring cycle failed: ${error.message}`);
        }
    }
    
    /**
     * Start enterprise health monitoring
     */
    start() {
        if (this.isRunning) {
            this.log('warn', 'Enterprise health monitor already running');
            return;
        }
        
        this.isRunning = true;
        this.state.metrics.uptime = Date.now();
        
        this.log('info', 'Starting enterprise health monitoring', { 
            interval: this.config.checkInterval,
            alertThresholds: this.config.alertThresholds
        });
        
        // Initial health check
        this.performHealthChecks();
        
        // Schedule periodic checks
        this.checkTimer = setInterval(() => {
            this.performHealthChecks();
        }, this.config.checkInterval);
        
        this.emit('started');
    }
    
    /**
     * Stop enterprise health monitoring
     */
    stop() {
        if (!this.isRunning) {
            this.log('warn', 'Enterprise health monitor not running');
            return;
        }
        
        this.isRunning = false;
        
        if (this.checkTimer) {
            clearInterval(this.checkTimer);
            this.checkTimer = null;
        }
        
        this.log('info', 'Enterprise health monitoring stopped');
        this.emit('stopped');
    }
    
    /**
     * Get current system status
     */
    getSystemStatus() {
        const uptime = Date.now() - this.state.metrics.uptime;
        const successRate = this.state.metrics.totalChecks > 0 
            ? (this.state.metrics.successfulChecks / this.state.metrics.totalChecks) * 100 
            : 0;
        
        return {
            status: this.isRunning ? 'running' : 'stopped',
            uptime,
            metrics: {
                ...this.state.metrics,
                successRate,
                uptimeHours: Math.floor(uptime / (1000 * 60 * 60))
            },
            circuitBreakers: Object.keys(this.state.circuitBreakers)
                .filter(id => this.state.circuitBreakers[id].state !== 'closed')
                .map(id => ({
                    instanceId: id,
                    state: this.state.circuitBreakers[id].state,
                    failures: this.state.circuitBreakers[id].failures
                })),
            config: this.config
        };
    }
}

module.exports = EnterpriseHealthMonitor;