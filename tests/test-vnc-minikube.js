#!/usr/bin/env node

const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');
const { createTestLogger } = require('../utils/logger');

const execAsync = promisify(exec);

// VNC test for minikube cluster
class MinikubeVNCTester {
    constructor() {
        this.results = [];
        this.screenshotDir = './vnc-screenshots';
        this.frontendUrl = null;
        this.logger = createTestLogger('test-vnc-minikube');
        
        // Ensure screenshot directory exists
        if (!fs.existsSync(this.screenshotDir)) {
            fs.mkdirSync(this.screenshotDir, { recursive: true });
        }
    }

    log(message, context = {}) {
        this.logger.info(message, context);
    }

    async getMinikubeServiceUrl() {
        try {
            this.log('Getting minikube frontend service URL...');
            const { stdout } = await execAsync('minikube service loco-loco-frontend -n loco --url');
            this.frontendUrl = stdout.trim();
            this.log(`Frontend URL: ${this.frontendUrl}`);
            return this.frontendUrl;
        } catch (error) {
            this.log(`Error getting service URL: ${error.message}`);
            return null;
        }
    }

    async testVNCConnection(instanceName) {
        return new Promise((resolve) => {
            if (!this.frontendUrl) {
                resolve({
                    instance: instanceName,
                    success: false,
                    error: 'No frontend URL available'
                });
                return;
            }

            // Extract port from URL (e.g., http://127.0.0.1:56260 -> 56260)
            const port = this.frontendUrl.split(':').pop();
            const wsUrl = `ws://127.0.0.1:${port}/proxy/vnc/${instanceName}/`;
            
            this.log(`Testing VNC connection to ${instanceName} via ${wsUrl}`);
            
            const ws = new WebSocket(wsUrl);
            let handshakeStep = 0;
            let testResult = {
                instance: instanceName,
                success: false,
                error: null,
                framebufferSize: null,
                desktopName: null,
                screenshotPath: null,
                wsUrl: wsUrl
            };

            const timeout = setTimeout(() => {
                this.log(`Test timeout for ${instanceName}`);
                ws.close();
                resolve(testResult);
            }, 15000);

            ws.on('open', () => {
                this.log(`WebSocket connected to ${instanceName}`);
            });

            ws.on('message', (data) => {
                this.log(`Step ${handshakeStep}: Received ${data.length} bytes from ${instanceName}`);
                
                if (handshakeStep === 0) {
                    // VNC server version
                    const serverVersion = data.toString();
                    this.log(`Server version: ${JSON.stringify(serverVersion)}`);
                    
                    const clientVersion = 'RFB 003.008\n';
                    this.log(`Sending client version: ${JSON.stringify(clientVersion)}`);
                    ws.send(clientVersion);
                    handshakeStep = 1;
                    
                } else if (handshakeStep === 1) {
                    // Security types
                    const numTypes = data[0];
                    this.log(`Number of security types: ${numTypes}`);
                    
                    if (numTypes > 0) {
                        for (let i = 0; i < numTypes; i++) {
                            this.log(`Security type ${i}: ${data[1 + i]}`);
                        }
                        
                        // Select "None" security (type 1)
                        this.log('Selecting security type 1 (None)');
                        ws.send(Buffer.from([1]));
                        handshakeStep = 2;
                    }
                    
                } else if (handshakeStep === 2) {
                    // Security result
                    const result = data.readUInt32BE(0);
                    this.log(`Security result: ${result}`);
                    
                    if (result === 0) {
                        this.log('Security handshake successful');
                        this.log('Sending ClientInit (shared=1)');
                        ws.send(Buffer.from([1]));
                        handshakeStep = 3;
                    } else {
                        testResult.error = 'Security handshake failed';
                        this.log('Security handshake failed');
                    }
                    
                } else if (handshakeStep === 3) {
                    // ServerInit
                    const width = data.readUInt16BE(0);
                    const height = data.readUInt16BE(2);
                    this.log(`Framebuffer size: ${width}x${height}`);
                    
                    // Parse name length and name
                    const nameLength = data.readUInt32BE(20);
                    const name = data.slice(24, 24 + nameLength).toString();
                    this.log(`Desktop name: "${name}"`);
                    
                    testResult.framebufferSize = { width, height };
                    testResult.desktopName = name;
                    testResult.success = true;
                    
                    this.log('VNC handshake complete!');
                    
                    // Save a simple success indicator
                    const successPath = path.join(this.screenshotDir, `${instanceName}-success.txt`);
                    fs.writeFileSync(successPath, `VNC Connection Successful\nInstance: ${instanceName}\nFramebuffer: ${width}x${height}\nDesktop: ${name}\nTimestamp: ${new Date().toISOString()}\nWS URL: ${wsUrl}`);
                    testResult.screenshotPath = successPath;
                    
                    clearTimeout(timeout);
                    ws.close();
                    resolve(testResult);
                }
            });

            ws.on('error', (err) => {
                this.log(`WebSocket error: ${err.message}`);
                testResult.error = err.message;
                clearTimeout(timeout);
                resolve(testResult);
            });

            ws.on('close', (code, reason) => {
                this.log(`WebSocket closed: ${code} ${reason?.toString()}`);
                clearTimeout(timeout);
                resolve(testResult);
            });
        });
    }

    async runClusterDiagnostics() {
        this.log('Running cluster diagnostics...');
        
        // Check cluster status
        try {
            const { stdout: podStatus } = await execAsync('kubectl get pods -n loco -o wide');
            this.log('Pod Status:');
            console.log(podStatus);
            
            const { stdout: serviceStatus } = await execAsync('kubectl get svc -n loco');
            this.log('Service Status:');
            console.log(serviceStatus);
            
        } catch (error) {
            this.log(`Error checking cluster status: ${error.message}`);
        }
    }

    async testClusterConnectivity() {
        this.log('Testing minikube cluster VNC connectivity...');
        
        // Get the frontend service URL
        await this.getMinikubeServiceUrl();
        
        // Run diagnostics
        await this.runClusterDiagnostics();
        
        // Test configurations
        const testConfigs = [
            { instance: 'instance-0', description: 'Primary emulator' },
            { instance: 'instance-1', description: 'Secondary emulator' },
            { instance: 'instance-2', description: 'Tertiary emulator' }
        ];
        
        for (const config of testConfigs) {
            this.log(`Testing ${config.instance} (${config.description})`);
            const result = await this.testVNCConnection(config.instance);
            this.results.push(result);
            
            // Small delay between tests
            await new Promise(resolve => setTimeout(resolve, 3000));
        }
        
        this.generateReport();
    }

    generateReport() {
        this.log('Generating test report...');
        
        const report = {
            timestamp: new Date().toISOString(),
            frontendUrl: this.frontendUrl,
            totalTests: this.results.length,
            successfulTests: this.results.filter(r => r.success).length,
            failedTests: this.results.filter(r => !r.success).length,
            results: this.results
        };
        
        // Save detailed report
        const reportPath = path.join(this.screenshotDir, 'vnc-minikube-test-report.json');
        fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
        
        // Print summary
        console.log('\n=== VNC Minikube Test Report ===');
        console.log(`Frontend URL: ${this.frontendUrl || 'Not available'}`);
        console.log(`Total Tests: ${report.totalTests}`);
        console.log(`Successful: ${report.successfulTests}`);
        console.log(`Failed: ${report.failedTests}`);
        console.log(`Report saved to: ${reportPath}`);
        console.log('\nDetailed Results:');
        
        this.results.forEach(result => {
            const status = result.success ? '✅ SUCCESS' : '❌ FAILED';
            console.log(`${status} ${result.instance}: ${result.error || 'Connected successfully'}`);
            if (result.framebufferSize) {
                console.log(`  Framebuffer: ${result.framebufferSize.width}x${result.framebufferSize.height}`);
            }
            if (result.screenshotPath) {
                console.log(`  Screenshot: ${result.screenshotPath}`);
            }
        });
        
        // Generate HTML report
        this.generateHTMLReport(report);
    }

    generateHTMLReport(report) {
        const htmlReport = `
<!DOCTYPE html>
<html>
<head>
    <title>VNC Minikube Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .stat { background: #e8f5e8; padding: 10px; border-radius: 5px; text-align: center; }
        .result { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .success { border-left: 5px solid #28a745; }
        .failure { border-left: 5px solid #dc3545; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>VNC Minikube Test Report</h1>
        <p>Generated: ${report.timestamp}</p>
        <p>Frontend URL: ${report.frontendUrl || 'Not available'}</p>
    </div>
    
    <div class="summary">
        <div class="stat">
            <h3>Total Tests</h3>
            <h2>${report.totalTests}</h2>
        </div>
        <div class="stat">
            <h3>Successful</h3>
            <h2 style="color: #28a745;">${report.successfulTests}</h2>
        </div>
        <div class="stat">
            <h3>Failed</h3>
            <h2 style="color: #dc3545;">${report.failedTests}</h2>
        </div>
    </div>
    
    <h2>Test Results</h2>
    ${report.results.map(result => `
        <div class="result ${result.success ? 'success' : 'failure'}">
            <h3>${result.instance}</h3>
            <p><strong>Status:</strong> ${result.success ? '✅ SUCCESS' : '❌ FAILED'}</p>
            ${result.error ? `<p><strong>Error:</strong> ${result.error}</p>` : ''}
            ${result.framebufferSize ? `<p><strong>Framebuffer:</strong> ${result.framebufferSize.width}x${result.framebufferSize.height}</p>` : ''}
            ${result.desktopName ? `<p><strong>Desktop:</strong> ${result.desktopName}</p>` : ''}
            ${result.screenshotPath ? `<p><strong>Success File:</strong> <a href="${result.screenshotPath}">${result.screenshotPath}</a></p>` : ''}
            ${result.wsUrl ? `<p><strong>WebSocket URL:</strong> ${result.wsUrl}</p>` : ''}
        </div>
    `).join('')}
    
    <h2>Raw Data</h2>
    <pre>${JSON.stringify(report, null, 2)}</pre>
</body>
</html>`;
        
        const htmlPath = path.join(this.screenshotDir, 'vnc-minikube-test-report.html');
        fs.writeFileSync(htmlPath, htmlReport);
        console.log(`HTML report saved to: ${htmlPath}`);
    }
}

// Run the tests
const tester = new MinikubeVNCTester();
tester.testClusterConnectivity().catch(console.error); 