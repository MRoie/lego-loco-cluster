/**
 * OSI Verification Unit Tests
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { verifyAllLayers } from './osiVerification';

// Mock globals
global.fetch = vi.fn();

// Mock WebSocket class
class MockWebSocket {
    constructor(url) {
        this.url = url;
        this.binaryType = 'blob';
        this.onopen = null;
        this.onmessage = null;
        this.onerror = null;
        this.onclose = null;

        // Register this instance so tests can access it
        if (global.mockWebSocketInstanceCallback) {
            global.mockWebSocketInstanceCallback(this);
        }
    }

    close() { }
    send() { }
}

global.WebSocket = MockWebSocket;

describe('OSI Verification', () => {
    beforeEach(() => {
        vi.clearAllMocks();
        vi.useFakeTimers();
        global.mockWebSocketInstanceCallback = null;

        // Default fetch mock for L3 check
        global.fetch.mockResolvedValue({
            ok: true,
            json: async () => ({})
        });
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it('should verify Layer 3 (API Reachability)', async () => {
        global.fetch.mockResolvedValueOnce({ ok: true }); // L3
        global.fetch.mockResolvedValueOnce({ // L4
            ok: true,
            json: async () => ({
                instances: [{ id: 'inst-1', probe: { reachable: true } }]
            })
        });

        // Mock WS to avoid errors
        global.mockWebSocketInstanceCallback = (ws) => {
            setTimeout(() => { if (ws.onopen) ws.onopen(); }, 10);
        };

        const promise = verifyAllLayers('inst-1', 'ws://test');
        await vi.runAllTimersAsync();
        const result = await promise;

        expect(result.layer3.status).toBe('ok');
    });

    it('should fail Layer 3 if API unreachable', async () => {
        global.fetch.mockRejectedValueOnce(new Error('Network error'));

        const promise = verifyAllLayers('inst-1', 'ws://test');
        await vi.runAllTimersAsync();
        const result = await promise;

        expect(result.layer3.status).toBe('failed');
        expect(result.layer4.status).toBe('pending');
    });

    it('should verify Layer 4 (TCP via Backend)', async () => {
        global.fetch.mockResolvedValueOnce({ ok: true }); // L3
        global.fetch.mockResolvedValueOnce({ // L4
            ok: true,
            json: async () => ({
                instances: [{ id: 'inst-1', probe: { reachable: true } }]
            })
        });

        global.mockWebSocketInstanceCallback = (ws) => {
            setTimeout(() => { if (ws.onopen) ws.onopen(); }, 10);
        };

        const promise = verifyAllLayers('inst-1', 'ws://test');
        await vi.runAllTimersAsync();
        const result = await promise;

        expect(result.layer4.status).toBe('ok');
    });

    it('should verify Layer 5 (WebSocket)', async () => {
        // Setup L3/L4 success
        global.fetch.mockResolvedValueOnce({ ok: true });
        global.fetch.mockResolvedValueOnce({
            ok: true,
            json: async () => ({ instances: [{ id: 'inst-1', probe: { reachable: true } }] })
        });

        // Control WS behavior
        global.mockWebSocketInstanceCallback = (ws) => {
            setTimeout(() => {
                if (ws.onopen) ws.onopen();
            }, 10);
        };

        const promise = verifyAllLayers('inst-1', 'ws://test');

        await vi.runAllTimersAsync();

        const result = await promise;
        expect(result.layer5.status).toBe('ok');
    });

    it('should verify Layer 7 (VNC Protocol)', async () => {
        // Setup L3/L4 success
        global.fetch.mockResolvedValueOnce({ ok: true });
        global.fetch.mockResolvedValueOnce({
            ok: true,
            json: async () => ({ instances: [{ id: 'inst-1', probe: { reachable: true } }] })
        });

        // Control WS behavior for handshake
        global.mockWebSocketInstanceCallback = (ws) => {
            setTimeout(() => {
                if (ws.onopen) ws.onopen(); // L5 success

                // L7 handshake response
                setTimeout(() => {
                    if (ws.onmessage) {
                        ws.onmessage({ data: 'RFB 003.008\n' });
                    }
                }, 10);
            }, 10);
        };

        const promise = verifyAllLayers('inst-1', 'ws://test');

        await vi.advanceTimersByTimeAsync(100);

        const result = await promise;
        expect(result.layer7.status).toBe('ok');
        expect(result.layer7.version).toBe('RFB 003.008');
    });
});
