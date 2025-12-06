/**
 * useVNCConnection Hook
 * Manages VNC connection state, metadata fetching, and retry logic.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { createLogger } from '../utils/logger';
import { metrics } from '../utils/metrics';
import { RetryStrategy } from '../utils/retry';

const logger = createLogger('useVNCConnection');

export const ConnectionState = {
    UNINITIALIZED: 'uninitialized',
    FETCHING_METADATA: 'fetching_metadata',
    CONNECTING: 'connecting',
    AUTHENTICATING: 'authenticating',
    CONNECTED: 'connected',
    DEGRADED: 'degraded',
    RECONNECTING: 'reconnecting',
    DISCONNECTED: 'disconnected',
    FAILED: 'failed'
};

export function useVNCConnection(instanceId, options = {}) {
    const [state, setState] = useState({
        connectionState: ConnectionState.UNINITIALIZED,
        instance: null,
        vncUrl: null,
        connected: false,
        error: null,
        diagnostics: null,
        metrics: {
            connectTime: null,
            frameRate: 0,
            latencyMs: null
        },
        retryCount: 0
    });

    const {
        autoConnect = true,
        retryAttempts = 5,
        onConnectionChange,
        onError
    } = options;

    // Persist retry strategy across renders
    const retryStrategyRef = useRef(null);
    if (!retryStrategyRef.current) {
        retryStrategyRef.current = new RetryStrategy(retryAttempts);
    }

    // Helper to update state and notify listeners
    const updateState = useCallback((updates) => {
        setState(prev => {
            const newState = { ...prev, ...updates };

            // Notify on state change
            if (onConnectionChange && newState.connectionState !== prev.connectionState) {
                onConnectionChange(newState.connectionState);
            }

            return newState;
        });
    }, [onConnectionChange]);

    const buildVNCUrl = (instanceId) => {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const host = window.location.host;
        return `${protocol}//${host}/proxy/vnc/${instanceId}/`;
    };

    const connect = useCallback(async () => {
        if (!instanceId) return;

        logger.info('Starting VNC connection process', { instanceId });
        updateState({ connectionState: ConnectionState.FETCHING_METADATA, error: null });
        metrics.incrementCounter('vnc_connection_attempts', { instance: instanceId });

        const startTime = Date.now();

        try {
            await retryStrategyRef.current.execute(async () => {
                // Step 1: Fetch instance metadata
                // We use the live endpoint to ensure the instance is actually ready
                const response = await fetch('/api/instances/live');
                if (!response.ok) {
                    throw new Error(`Failed to fetch instance metadata: ${response.status}`);
                }

                const data = await response.json();
                const instance = data.instances.find(i => i.id === instanceId);

                if (!instance) {
                    throw new Error(`Instance ${instanceId} not found in active discovery`);
                }

                // Step 2: Build URL
                const vncUrl = buildVNCUrl(instanceId);

                // Step 3: Run OSI Verification (if enabled)
                // We do this before marking as connecting to catch issues early
                // In production, this might be gated or run in parallel
                let diagnostics = null;
                try {
                    diagnostics = await verifyAllLayers(instanceId, vncUrl);
                    logger.info('Connection diagnostics', { diagnostics });
                } catch (diagErr) {
                    logger.warn('Diagnostics failed', { error: diagErr.message });
                }

                // Step 4: Update state to trigger connection in UI component
                updateState({
                    instance,
                    vncUrl,
                    diagnostics,
                    connectionState: ConnectionState.CONNECTING
                });

                if (instance.status !== 'ready') {
                    // We still allow connecting if not ready, but log it
                    logger.warn(`Instance ${instanceId} is not ready (status: ${instance.status})`);
                }

                logger.info('VNC metadata fetched and URL prepared', {
                    instanceId,
                    vncUrl,
                    discoveryStatus: instance.status
                });

                return true;
            }, (attempt, delay, error) => {
                // On retry
                updateState({
                    connectionState: ConnectionState.RECONNECTING,
                    retryCount: attempt
                });
                metrics.incrementCounter('vnc_connection_retries', { instance: instanceId });
            });

        } catch (error) {
            logger.error('VNC connection process failed', { instanceId, error: error.message });

            updateState({
                connectionState: ConnectionState.FAILED,
                error
            });

            metrics.incrementCounter('vnc_connection_failures', { instance: instanceId });

            if (onError) onError(error);
        }
    }, [instanceId, updateState, onError]);

    const disconnect = useCallback(() => {
        logger.info('Disconnecting VNC', { instanceId });
        updateState({
            connectionState: ConnectionState.DISCONNECTED,
            connected: false,
            vncUrl: null
        });
        retryStrategyRef.current.reset();
    }, [instanceId, updateState]);

    // Auto-connect effect
    useEffect(() => {
        if (autoConnect && instanceId && state.connectionState === ConnectionState.UNINITIALIZED) {
            connect();
        }
    }, [instanceId, autoConnect, state.connectionState, connect]);

    return {
        state,
        connect,
        disconnect,
        updateState // Exposed for component to update connection status (e.g. onConnect callback)
    };
}
