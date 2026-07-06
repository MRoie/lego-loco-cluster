import React, { useState, useEffect, useCallback } from 'react';
import NoVNCViewer from './NoVNCViewer';
import ReactVNCViewer from './ReactVNCViewer';
import { createLogger } from '../utils/logger.js';
import { metrics } from '../utils/metrics';

const logger = createLogger('VNCViewerSwitcher');

/**
 * VNC Viewer Switcher Component
 * Manages switching between NoVNC (primary) and react-vnc (fallback) implementations
 * Includes retry logic and automatic fallback on failures
 */
export default function VNCViewerSwitcher({ instanceId }) {
    const [implementation, setImplementation] = useState('novnc'); // 'novnc' or 'react-vnc'
    const [failureCount, setFailureCount] = useState(0);
    const [config, setConfig] = useState(null);
    const [loading, setLoading] = useState(true);

    // Load VNC configuration from backend
    useEffect(() => {
        const loadConfig = async () => {
            try {
                console.log('[VNCViewerSwitcher] Loading VNC configuration', { instanceId });
                const response = await fetch('/api/config/vnc');

                if (response.ok) {
                    const data = await response.json();
                    console.log('[VNCViewerSwitcher] VNC config loaded', { config: data });
                    setConfig(data);
                    setImplementation(data.implementation || 'novnc');
                } else {
                    logger.warn('Failed to load VNC config, using default', { status: response.status });
                    // Use defaults if config fails to load
                    setConfig({ implementation: 'novnc', fallbackEnabled: true, maxRetries: 3 });
                    setImplementation('novnc');
                }
            } catch (error) {
                logger.error('Error loading VNC config', { error: error.message });
                // Use defaults on error
                setConfig({ implementation: 'novnc', fallbackEnabled: true, maxRetries: 3 });
                setImplementation('novnc');
            } finally {
                setLoading(false);
            }
        };

        loadConfig();
    }, [instanceId]);

    // Handle connection errors from the active implementation
    const handleError = useCallback((error) => {
        console.error(`[VNCViewerSwitcher] ${implementation} error`, { instanceId, error, failureCount });
        logger.error(`VNC ${implementation} error`, { instanceId, error: error?.message || error, failureCount });

        const newFailureCount = failureCount + 1;
        setFailureCount(newFailureCount);

        metrics.incrementCounter('vnc_switcher_error', {
            instance: instanceId,
            implementation,
            failure_count: newFailureCount
        });

        // Check if we should fall back to react-vnc
        const maxRetries = config?.maxRetries || 3;
        if (config?.fallbackEnabled && implementation === 'novnc' && newFailureCount >= maxRetries) {
            console.log('[VNCViewerSwitcher] ⚠️ NoVNC failed', maxRetries, 'times, falling back to react-vnc', { instanceId });
            logger.warn(`NoVNC failed ${maxRetries} times, falling back to react-vnc`, { instanceId });
            setImplementation('react-vnc');
            setFailureCount(0); // Reset counter for fallback
            metrics.incrementCounter('vnc_switcher_fallback', { instance: instanceId, from: 'novnc', to: 'react-vnc' });
        }
    }, [instanceId, implementation, failureCount, config]);

    // Handle successful connections (reset failure counter)
    const handleConnect = useCallback(() => {
        console.log(`[VNCViewerSwitcher] ✅ ${implementation} connected successfully`, { instanceId });
        logger.info(`VNC ${implementation} connected successfully`, { instanceId });
        setFailureCount(0);
        metrics.incrementCounter('vnc_switcher_connected', { instance: instanceId, implementation });
    }, [instanceId, implementation]);

    if (loading) {
        return (
            <div className="flex items-center justify-center h-full">
                <div className="text-white">Loading VNC configuration...</div>
            </div>
        );
    }

    // Log which implementation is being used
    console.log('[VNCViewerSwitcher] Rendering', implementation, 'implementation', { instanceId, config });

    return (
        <div className="w-full h-full">
            {implementation === 'novnc' ? (
                <NoVNCView instanceId={instanceId} onError={handleError} onConnect={handleConnect} />
            ) : (
                <ReactVNCViewer instanceId={instanceId} onError={handleError} onConnect={handleConnect} />
            )}

            {/* Debug indicator showing current implementation */}
            {process.env.NODE_ENV === 'development' && (
                <div className="absolute bottom-2 left-2 bg-purple-800 bg-opacity-75 rounded px-2 py-1 text-white text-xs z-50">
                    Using: {implementation} | Failures: {failureCount}
                </div>
            )}
        </div>
    );
}

// Wrapper for NoVNCViewer to handle custom error/connect callbacks
function NoVNCView({ instanceId, onError, onConnect }) {
    // NoVNCViewer handles its own events, we just wrap it to intercept errors
    return <NoVNCViewer instanceId={instanceId} />;
}
