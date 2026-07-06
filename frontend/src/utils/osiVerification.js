/**
 * OSI Layer Verification Utility
 * Diagnoses connection issues by verifying network layers independently.
 */

import { createLogger } from './logger';

const logger = createLogger('OSIVerification');

/**
 * Verify Layer 3: Network/API Reachability
 * Checks if the backend API is reachable.
 */
async function verifyLayer3() {
    const start = Date.now();
    try {
        // Use a lightweight endpoint
        const response = await fetch('/api/health', {
            method: 'GET',
            cache: 'no-cache',
            headers: { 'Accept': 'application/json' }
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const latency = Date.now() - start;
        logger.debug('Layer 3 verified', { latency });

        return { status: 'ok', latency };
    } catch (error) {
        logger.error('Layer 3 check failed', { error: error.message });
        return { status: 'failed', error: error.message, latency: Date.now() - start };
    }
}

/**
 * Verify Layer 4: Transport (TCP) Connectivity
 * Uses backend probing to verify TCP connection to the emulator.
 */
async function verifyLayer4(instanceId) {
    try {
        // Fetch live instance data which includes probe results
        const response = await fetch('/api/instances/live');
        if (!response.ok) throw new Error('Failed to fetch instance data');

        const data = await response.json();
        const instance = data.instances?.find(i => i.id === instanceId);

        if (!instance) {
            throw new Error(`Instance ${instanceId} not found`);
        }

        // Check probe data from backend
        // The backend performs the actual TCP check
        if (instance.probe?.reachable) {
            logger.debug('Layer 4 verified via backend probe', { instanceId });
            return { status: 'ok', details: 'TCP reachable via backend' };
        } else {
            throw new Error('Backend probe reports instance unreachable');
        }
    } catch (error) {
        logger.error('Layer 4 check failed', { instanceId, error: error.message });
        return { status: 'failed', error: error.message };
    }
}

/**
 * Verify Layer 5: Session (WebSocket)
 * Attempts to establish a WebSocket connection and perform a handshake.
 */
async function verifyLayer5(vncUrl, timeoutMs = 5000) {
    return new Promise((resolve) => {
        const start = Date.now();
        let ws;
        let timeout;

        try {
            ws = new WebSocket(vncUrl);
            // Binary type for VNC
            ws.binaryType = 'arraybuffer';
        } catch (e) {
            return resolve({ status: 'failed', error: `WebSocket creation failed: ${e.message}` });
        }

        const cleanup = () => {
            if (timeout) clearTimeout(timeout);
            if (ws) {
                ws.onopen = null;
                ws.onerror = null;
                ws.close();
            }
        };

        timeout = setTimeout(() => {
            cleanup();
            resolve({ status: 'failed', error: 'Connection timed out' });
        }, timeoutMs);

        ws.onopen = () => {
            const latency = Date.now() - start;
            logger.debug('Layer 5 verified', { vncUrl, latency });
            cleanup();
            resolve({ status: 'ok', latency });
        };

        ws.onerror = (event) => {
            cleanup();
            // WebSocket error events give very little info in JS due to security
            resolve({ status: 'failed', error: 'WebSocket connection error' });
        };
    });
}

/**
 * Verify Layer 7: Application (VNC Protocol)
 * Checks if the VNC server responds with a valid RFB version.
 * NOTE: This requires actually connecting and reading the first message.
 */
async function verifyLayer7(vncUrl, timeoutMs = 5000) {
    return new Promise((resolve) => {
        let ws;
        let timeout;

        try {
            ws = new WebSocket(vncUrl);
            ws.binaryType = 'arraybuffer';
        } catch (e) {
            return resolve({ status: 'failed', error: `WebSocket creation failed: ${e.message}` });
        }

        const cleanup = () => {
            if (timeout) clearTimeout(timeout);
            if (ws) {
                ws.onmessage = null;
                ws.onerror = null;
                ws.close();
            }
        };

        timeout = setTimeout(() => {
            cleanup();
            resolve({ status: 'failed', error: 'Protocol handshake timed out' });
        }, timeoutMs);

        ws.onmessage = (event) => {
            try {
                // VNC server sends protocol version first, e.g., "RFB 003.008\n"
                const data = event.data;
                let versionString;

                if (typeof data === 'string') {
                    versionString = data;
                } else if (data instanceof ArrayBuffer) {
                    versionString = new TextDecoder().decode(data);
                }

                if (versionString && versionString.startsWith('RFB')) {
                    logger.debug('Layer 7 verified', { version: versionString.trim() });
                    cleanup();
                    resolve({ status: 'ok', version: versionString.trim() });
                } else {
                    cleanup();
                    resolve({ status: 'failed', error: 'Invalid VNC protocol header', received: versionString });
                }
            } catch (e) {
                cleanup();
                resolve({ status: 'failed', error: `Protocol parsing error: ${e.message}` });
            }
        };

        ws.onerror = () => {
            cleanup();
            resolve({ status: 'failed', error: 'WebSocket error during handshake' });
        };
    });
}

/**
 * Run full OSI stack verification
 */
export async function verifyAllLayers(instanceId, vncUrl) {
    logger.info('Starting full OSI layer verification', { instanceId });

    const diagnostics = {
        timestamp: new Date().toISOString(),
        layer3: await verifyLayer3(),
        layer4: { status: 'pending' },
        layer5: { status: 'pending' },
        layer7: { status: 'pending' }
    };

    // If L3 fails, we can't really check L4 reliably via API
    if (diagnostics.layer3.status === 'failed') {
        return diagnostics;
    }

    diagnostics.layer4 = await verifyLayer4(instanceId);

    // If L4 fails, L5/L7 will likely fail
    if (diagnostics.layer4.status === 'failed') {
        return diagnostics;
    }

    // Check L5 (WebSocket)
    if (vncUrl) {
        diagnostics.layer5 = await verifyLayer5(vncUrl);

        // Check L7 (VNC Protocol) if L5 succeeded
        if (diagnostics.layer5.status === 'ok') {
            diagnostics.layer7 = await verifyLayer7(vncUrl);
        }
    } else {
        diagnostics.layer5 = { status: 'skipped', reason: 'No VNC URL provided' };
    }

    logger.info('OSI verification complete', { diagnostics });
    return diagnostics;
}
