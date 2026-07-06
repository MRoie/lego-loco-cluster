import React, { useState } from 'react';

/**
 * VNC Debug Panel
 * Displays real-time connection state, metrics, and diagnostics.
 * Only visible in development mode or when debug is enabled.
 */
export default function VNCDebugPanel({ instanceId, state }) {
    const [expanded, setExpanded] = useState(false);
    const [showDiagnostics, setShowDiagnostics] = useState(false);

    // Only show in dev mode or if explicitly enabled via env
    const isDev = import.meta.env.MODE === 'development' || import.meta.env.VITE_SHOW_DEBUG_PANEL === 'true';
    if (!isDev) return null;

    const {
        connectionState,
        vncUrl,
        metrics,
        diagnostics,
        error,
        retryCount
    } = state;

    // Helper to format duration
    const formatDuration = (ms) => {
        if (!ms) return '-';
        return `${ms.toFixed(0)}ms`;
    };

    // Helper to format timestamp
    const formatTime = (isoString) => {
        if (!isoString) return '-';
        return new Date(isoString).toLocaleTimeString();
    };

    // Status color helper
    const getStatusColor = (status) => {
        switch (status) {
            case 'ok': return 'text-green-400';
            case 'failed': return 'text-red-400';
            case 'pending': return 'text-yellow-400';
            case 'skipped': return 'text-gray-400';
            default: return 'text-white';
        }
    };

    if (!expanded) {
        return (
            <button
                onClick={() => setExpanded(true)}
                className="absolute bottom-0 right-0 bg-black bg-opacity-75 text-white text-xs px-2 py-1 rounded-tl hover:bg-opacity-90 z-50 font-mono"
            >
                🐞 Debug
            </button>
        );
    }

    return (
        <div className="absolute bottom-0 left-0 right-0 bg-black bg-opacity-90 text-white text-xs font-mono p-2 z-50 border-t border-gray-700 max-h-64 overflow-y-auto">
            <div className="flex justify-between items-start mb-2">
                <h3 className="font-bold text-yellow-400">VNC Debug: {instanceId}</h3>
                <button onClick={() => setExpanded(false)} className="text-gray-400 hover:text-white">✕</button>
            </div>

            <div className="grid grid-cols-2 gap-x-4 gap-y-1">
                {/* State & URL */}
                <div className="col-span-2">
                    <span className="text-gray-400">State:</span>
                    <span className={`ml-1 font-bold ${error ? 'text-red-400' : 'text-blue-400'}`}>
                        {connectionState}
                    </span>
                    {retryCount > 0 && <span className="ml-2 text-yellow-500">(Retry #{retryCount})</span>}
                </div>
                <div className="col-span-2 truncate" title={vncUrl}>
                    <span className="text-gray-400">URL:</span> {vncUrl || '-'}
                </div>

                {/* Metrics */}
                <div>
                    <span className="text-gray-400">FPS:</span> {metrics.frameRate?.toFixed(1) || 0}
                </div>
                <div>
                    <span className="text-gray-400">Latency:</span> {formatDuration(metrics.latencyMs)}
                </div>
                <div>
                    <span className="text-gray-400">Connect Time:</span> {formatDuration(metrics.connectTime)}
                </div>

                {/* Error Display */}
                {error && (
                    <div className="col-span-2 mt-1 p-1 bg-red-900 bg-opacity-50 rounded border border-red-800 text-red-200 break-words">
                        {error.message || String(error)}
                    </div>
                )}
            </div>

            {/* Diagnostics Section */}
            {diagnostics && (
                <div className="mt-2 border-t border-gray-700 pt-1">
                    <div
                        className="flex justify-between cursor-pointer hover:bg-gray-800 p-1 rounded"
                        onClick={() => setShowDiagnostics(!showDiagnostics)}
                    >
                        <span className="font-bold">OSI Diagnostics</span>
                        <span>{showDiagnostics ? '▼' : '▶'}</span>
                    </div>

                    {showDiagnostics && (
                        <div className="pl-2 space-y-1 mt-1">
                            <div className="text-gray-500 text-[10px]">Run at: {formatTime(diagnostics.timestamp)}</div>

                            {/* Layer 3 */}
                            <div className="flex justify-between">
                                <span>L3 (Network):</span>
                                <span className={getStatusColor(diagnostics.layer3?.status)}>
                                    {diagnostics.layer3?.status} ({formatDuration(diagnostics.layer3?.latency)})
                                </span>
                            </div>

                            {/* Layer 4 */}
                            <div className="flex justify-between">
                                <span>L4 (TCP):</span>
                                <span className={getStatusColor(diagnostics.layer4?.status)}>
                                    {diagnostics.layer4?.status}
                                </span>
                            </div>

                            {/* Layer 5 */}
                            <div className="flex justify-between">
                                <span>L5 (WebSocket):</span>
                                <span className={getStatusColor(diagnostics.layer5?.status)}>
                                    {diagnostics.layer5?.status} {diagnostics.layer5?.latency ? `(${formatDuration(diagnostics.layer5?.latency)})` : ''}
                                </span>
                            </div>

                            {/* Layer 7 */}
                            <div className="flex justify-between">
                                <span>L7 (VNC):</span>
                                <span className={getStatusColor(diagnostics.layer7?.status)}>
                                    {diagnostics.layer7?.status}
                                </span>
                            </div>

                            {/* Detailed Error if any */}
                            {(diagnostics.layer5?.error || diagnostics.layer7?.error) && (
                                <div className="text-red-400 text-[10px] mt-1">
                                    {diagnostics.layer5?.error || diagnostics.layer7?.error}
                                </div>
                            )}
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}
