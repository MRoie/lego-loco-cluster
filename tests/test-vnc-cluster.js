#!/usr/bin/env node

const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

// Configuration
const TEST_CONFIG = {
    baseUrl: 'ws://localhost:3000/proxy/vnc',
    instances: ['instance-0', 'instance-1', 'instance-2', 'instance-3', 'instance-4', 'instance-5', 'instance-6', 'instance-7', 'instance-8'],
    timeout: 30000,
    screenshotDir: './vnc-screenshots'
};

// Ensure screenshot directory exists
if (!fs.existsSync(TEST_CONFIG.screenshotDir)) {
    fs.mkdirSync(TEST_CONFIG.screenshotDir, { recursive: true });
}

class VNCTester {
    constructor() {
        this.results = [];
        this.currentTest = null;
    }

    log(message, instance = 'GLOBAL') {
        const timestamp = new Date().toISOString();
        console.log(`[${timestamp}] [${instance}] ${message}`);
    }

    async testVNCConnection(instance) {
        return new Promise((resolve) => {
            this.log(`Starting VNC test for ${instance}`, instance);
            
            const ws = new WebSocket(`${TEST_CONFIG.baseUrl}/${instance}/`);
            let handshakeStep = 0;
            let framebufferData = [];
            let testResult = {
                instance,
                success: false,
                error: null,
                framebufferSize: null,
                desktopName: null,
                screenshotPath: null
            };

            const timeout = setTimeout(() => {
                this.log(`Test timeout for ${instance}`, instance);
                ws.close();
                resolve(testResult);
            }, TEST_CONFIG.timeout);

            ws.on('open', () => {
                this.log(`WebSocket connected for ${instance}`, instance);
            });

            ws.on('message', (data) => {
                this.log(`Step ${handshakeStep}: Received ${data.length} bytes`, instance);
                
                if (handshakeStep === 0) {
                    // VNC server version
                    const serverVersion = data.toString();
                    this.log(`Server version: ${JSON.stringify(serverVersion)}`, instance);
                    
                    const clientVersion = 'RFB 003.008\n';
                    this.log(`Sending client version: ${JSON.stringify(clientVersion)}`, instance);
                    ws.send(clientVersion);
                    handshakeStep = 1;
                    
                } else if (handshakeStep === 1) {
                    // Security types
                    const numTypes = data[0];
                    this.log(`Number of security types: ${numTypes}`, instance);
                    
                    if (numTypes > 0) {
                        for (let i = 0; i < numTypes; i++) {
                            this.log(`Security type ${i}: ${data[1 + i]}`, instance);
                        }
                        
                        // Select "None" security (type 1)
                        this.log('Selecting security type 1 (None)', instance);
                        ws.send(Buffer.from([1]));
                        handshakeStep = 2;
                    }
                    
                } else if (handshakeStep === 2) {
                    // Security result
                    const result = data.readUInt32BE(0);
                    this.log(`Security result: ${result}`, instance);
                    
                    if (result === 0) {
                        this.log('Security handshake successful', instance);
                        this.log('Sending ClientInit (shared=1)', instance);
                        ws.send(Buffer.from([1]));
                        handshakeStep = 3;
                    } else {
                        testResult.error = 'Security handshake failed';
                        this.log('Security handshake failed', instance);
                    }
                    
                } else if (handshakeStep === 3) {
                    // ServerInit
                    const width = data.readUInt16BE(0);
                    const height = data.readUInt16BE(2);
                    this.log(`Framebuffer size: ${width}x${height}`, instance);
                    
                    // Parse name length and name
                    const nameLength = data.readUInt32BE(20);
                    const name = data.slice(24, 24 + nameLength).toString();
                    this.log(`Desktop name: "${name}"`, instance);
                    
                    testResult.framebufferSize = { width, height };
                    testResult.desktopName = name;
                    
                    this.log('VNC handshake complete!', instance);
                    handshakeStep = 4;
                    
                    // Request screen update
                    setTimeout(() => {
                        this.log('Requesting framebuffer update...', instance);
                        const updateRequest = Buffer.alloc(10);
                        updateRequest[0] = 3; // FramebufferUpdateRequest
                        updateRequest[1] = 0; // incremental = 0 (full update)
                        updateRequest.writeUInt16BE(0, 2); // x
                        updateRequest.writeUInt16BE(0, 4); // y
                        updateRequest.writeUInt16BE(width, 6); // width
                        updateRequest.writeUInt16BE(height, 8); // height
                        ws.send(updateRequest);
                    }, 1000);
                    
                } else {
                    // Framebuffer updates
                    this.log(`Framebuffer data received: ${data.length} bytes`, instance);
                    framebufferData.push(data);
                    
                    // Save screenshot after receiving some data
                    if (framebufferData.length >= 1) {
                        const screenshotPath = path.join(TEST_CONFIG.screenshotDir, `${instance}-screenshot.raw`);
                        const combinedData = Buffer.concat(framebufferData);
                        fs.writeFileSync(screenshotPath, combinedData);
                        
                        testResult.success = true;
                        testResult.screenshotPath = screenshotPath;
                        this.log(`Screenshot saved: ${screenshotPath} (${combinedData.length} bytes)`, instance);
                        
                        clearTimeout(timeout);
                        ws.close();
                        resolve(testResult);
                    }
                }
            });

            ws.on('error', (err) => {
                this.log(`WebSocket error: ${err.message}`, instance);
                testResult.error = err.message;
                clearTimeout(timeout);
                resolve(testResult);
            });

            ws.on('close', (code, reason) => {
                this.log(`WebSocket closed: ${code} ${reason?.toString()}`, instance);
                clearTimeout(timeout);
                resolve(testResult);
            });
        });
    }

    async runAllTests() {
        this.log('Starting VNC cluster connectivity tests...');
        
        for (const instance of TEST_CONFIG.instances) {
            this.log(`Testing ${instance}...`);
            const result = await this.testVNCConnection(instance);
            this.results.push(result);
            
            // Small delay between tests
            await new Promise(resolve => setTimeout(resolve, 1000));
        }
        
        this.generateReport();
    }

    generateReport() {
        this.log('Generating test report...');
        
        const report = {
            timestamp: new Date().toISOString(),
            totalTests: this.results.length,
            successfulTests: this.results.filter(r => r.success).length,
            failedTests: this.results.filter(r => !r.success).length,
            results: this.results
        };
        
        // Save detailed report
        const reportPath = path.join(TEST_CONFIG.screenshotDir, 'vnc-test-report.json');
        fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
        
        // Print summary
        console.log('\n=== VNC Cluster Test Report ===');
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
    <title>VNC Cluster Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .stat { background: #e8f5e8; padding: 10px; border-radius: 5px; text-align: center; }
        .result { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .success { border-left: 5px solid #28a745; }
        .failure { border-left: 5px solid #dc3545; }
        .screenshot { max-width: 300px; border: 1px solid #ccc; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>VNC Cluster Test Report</h1>
        <p>Generated: ${report.timestamp}</p>
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
            ${result.screenshotPath ? `<p><strong>Screenshot:</strong> <a href="${result.screenshotPath}">${result.screenshotPath}</a></p>` : ''}
        </div>
    `).join('')}
    
    <h2>Raw Data</h2>
    <pre>${JSON.stringify(report, null, 2)}</pre>
</body>
</html>`;
        
        const htmlPath = path.join(TEST_CONFIG.screenshotDir, 'vnc-test-report.html');
        fs.writeFileSync(htmlPath, htmlReport);
        console.log(`HTML report saved to: ${htmlPath}`);
    }
}

// Run the tests
const tester = new VNCTester();
tester.runAllTests().catch(console.error); 