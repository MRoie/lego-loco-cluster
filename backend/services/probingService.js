const net = require('net');
const http = require('http');
const logger = require('../utils/logger');

class ProbingService {
    constructor(timeout = 2000) {
        this.timeout = timeout;
    }

    /**
     * Probe an instance's services
     * @param {Object} instance - The instance object with addresses and ports
     * @returns {Promise<Object>} - Probe results
     */
    async probeInstance(instance) {
        const ip = instance.addresses?.podIP;
        if (!ip) {
            return {
                reachable: false,
                services: {
                    vnc: { status: 'unknown', error: 'No IP' },
                    health: { status: 'unknown', error: 'No IP' }
                },
                timestamp: new Date().toISOString()
            };
        }

        const vncPort = instance.ports?.vnc || 5901;
        const healthPort = instance.ports?.health || 8080;

        const [vncResult, healthResult] = await Promise.all([
            this.checkVnc(ip, vncPort),
            this.checkHttp(`http://${ip}:${healthPort}/health`)
        ]);

        const isReachable = vncResult.status === 'ok' || healthResult.status === 'ok';

        return {
            reachable: isReachable,
            services: {
                vnc: vncResult,
                health: healthResult
            },
            timestamp: new Date().toISOString()
        };
    }

    /**
     * Check TCP connection and basic VNC handshake
     */
    checkVnc(host, port) {
        return new Promise((resolve) => {
            const socket = new net.Socket();
            let status = 'failed';
            let error = null;
            let protocolVersion = null;

            const timer = setTimeout(() => {
                socket.destroy();
                resolve({ status: 'timeout', error: 'Connection timed out' });
            }, this.timeout);

            socket.connect(port, host, () => {
                // Connected, wait for data (RFB handshake)
            });

            socket.on('data', (data) => {
                const message = data.toString();
                if (message.startsWith('RFB')) {
                    status = 'ok';
                    protocolVersion = message.trim();
                } else {
                    status = 'protocol_error';
                    error = 'Invalid VNC handshake';
                }
                clearTimeout(timer);
                socket.destroy();
                resolve({ status, protocolVersion });
            });

            socket.on('error', (err) => {
                clearTimeout(timer);
                resolve({ status: 'failed', error: err.message });
            });
        });
    }

    /**
     * Check HTTP endpoint
     */
    checkHttp(url) {
        return new Promise((resolve) => {
            const req = http.get(url, { timeout: this.timeout }, (res) => {
                const { statusCode } = res;
                res.resume(); // Consume response to free memory

                if (statusCode >= 200 && statusCode < 300) {
                    resolve({ status: 'ok', statusCode });
                } else {
                    resolve({ status: 'failed', statusCode, error: `HTTP ${statusCode}` });
                }
            });

            req.on('error', (err) => {
                resolve({ status: 'failed', error: err.message });
            });

            req.on('timeout', () => {
                req.destroy();
                resolve({ status: 'timeout', error: 'Request timed out' });
            });
        });
    }
}

module.exports = new ProbingService();
