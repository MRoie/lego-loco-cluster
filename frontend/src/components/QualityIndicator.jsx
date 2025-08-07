import React, { useState, useEffect } from 'react';

/**
 * Quality Indicator Component for Individual Instance Cards
 * Shows real-time quality metrics for a specific instance
 */
export default function QualityIndicator({ instanceId, compact = false }) {
  const [qualityMetrics, setQualityMetrics] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);

  // Fetch quality metrics for this specific instance
  const fetchInstanceQuality = async () => {
    try {
      const response = await fetch(`/api/quality/metrics/${instanceId}`);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const metrics = await response.json();
      setQualityMetrics(metrics);
      setError(null);
      setIsLoading(false);
    } catch (err) {
      console.error(`Failed to fetch quality for ${instanceId}:`, err);
      setError(err.message);
      setIsLoading(false);
    }
  };

  // Auto-refresh quality data
  useEffect(() => {
    if (!instanceId) return;
    
    fetchInstanceQuality();
    const interval = setInterval(fetchInstanceQuality, 5000); // Update every 5 seconds
    
    return () => clearInterval(interval);
  }, [instanceId]);

  // Get color class based on quality
  const getQualityColor = (quality) => {
    switch (quality) {
      case 'excellent': return 'text-green-400';
      case 'good': return 'text-blue-400';
      case 'fair': return 'text-yellow-400';
      case 'poor': return 'text-orange-400';
      case 'error':
      case 'unavailable': return 'text-red-400';
      default: return 'text-gray-400';
    }
  };

  // Get background color for indicators
  const getQualityBg = (quality) => {
    switch (quality) {
      case 'excellent': return 'bg-green-500';
      case 'good': return 'bg-blue-500';
      case 'fair': return 'bg-yellow-500';
      case 'poor': return 'bg-orange-500';
      case 'error':
      case 'unavailable': return 'bg-red-500';
      default: return 'bg-gray-500';
    }
  };

  // Get status icon
  const getStatusIcon = (available, responsive = null) => {
    if (available && (responsive === null || responsive)) return '✓';
    if (available && responsive === false) return '⚠';
    return '✗';
  };

  if (isLoading) {
    return (
      <div className={`${compact ? 'text-xs' : 'text-sm'} text-gray-400`}>
        <div className="animate-pulse">Loading...</div>
      </div>
    );
  }

  if (error || !qualityMetrics) {
    return (
      <div className={`${compact ? 'text-xs' : 'text-sm'} text-red-400`}>
        <div className="flex items-center">
          <span className="w-2 h-2 bg-red-500 rounded-full mr-1"></span>
          Quality: Error
        </div>
      </div>
    );
  }

  const { availability, quality } = qualityMetrics;

  if (compact) {
    // Compact mode for instance cards
    return (
      <div className="text-xs space-y-1">
        {/* Overall Quality Indicator */}
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Quality:</span>
          <div className="flex items-center">
            <div className={`w-2 h-2 rounded-full mr-1 ${getQualityBg(quality.audioQuality)}`}></div>
            <span className={getQualityColor(quality.audioQuality)}>
              {quality.audioQuality}
            </span>
          </div>
        </div>

        {/* Connection Status */}
        <div className="flex items-center justify-between">
          <span className="text-gray-300">VNC:</span>
          <span className={availability.vnc ? 'text-green-400' : 'text-red-400'}>
            {getStatusIcon(availability.vnc)}
          </span>
        </div>

        {/* Audio Status */}
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Audio:</span>
          <span className={availability.audio ? 'text-green-400' : 'text-red-400'}>
            {getStatusIcon(availability.audio)}
          </span>
        </div>

        {/* Controls Status */}
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Controls:</span>
          <span className={quality.controlsResponsive ? 'text-green-400' : 'text-red-400'}>
            {getStatusIcon(availability.controls, quality.controlsResponsive)}
          </span>
        </div>

        {/* Latency */}
        {quality.connectionLatency !== null && (
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Latency:</span>
            <span className={getQualityColor(quality.audioQuality)}>
              {quality.connectionLatency}ms
            </span>
          </div>
        )}
      </div>
    );
  }

  // Full mode for detailed views
  return (
    <div className="bg-gray-800 rounded-lg p-3 border border-gray-700">
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-sm font-semibold text-white">Stream Quality</h4>
        <div className={`w-3 h-3 rounded-full ${getQualityBg(quality.audioQuality)}`}></div>
      </div>

      <div className="space-y-2 text-xs">
        {/* Availability Grid */}
        <div className="grid grid-cols-2 gap-2">
          <div className="flex items-center justify-between">
            <span className="text-gray-300">VNC:</span>
            <span className={availability.vnc ? 'text-green-400' : 'text-red-400'}>
              {getStatusIcon(availability.vnc)} {availability.vnc ? 'Available' : 'Unavailable'}
            </span>
          </div>
          
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Stream:</span>
            <span className={availability.stream ? 'text-green-400' : 'text-red-400'}>
              {getStatusIcon(availability.stream)} {availability.stream ? 'Available' : 'Unavailable'}
            </span>
          </div>
          
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Audio:</span>
            <span className={availability.audio ? 'text-green-400' : 'text-red-400'}>
              {getStatusIcon(availability.audio)} {availability.audio ? 'Detected' : 'None'}
            </span>
          </div>
          
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Controls:</span>
            <span className={quality.controlsResponsive ? 'text-green-400' : 'text-red-400'}>
              {getStatusIcon(availability.controls, quality.controlsResponsive)} {quality.controlsResponsive ? 'Responsive' : 'Unresponsive'}
            </span>
          </div>
        </div>

        {/* Quality Metrics */}
        <div className="border-t border-gray-700 pt-2 space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Overall Quality:</span>
            <span className={getQualityColor(quality.audioQuality)}>
              {quality.audioQuality}
            </span>
          </div>
          
          {quality.connectionLatency !== null && (
            <div className="flex items-center justify-between">
              <span className="text-gray-300">Latency:</span>
              <span className={getQualityColor(quality.audioQuality)}>
                {quality.connectionLatency}ms
              </span>
            </div>
          )}
          
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Frame Rate:</span>
            <span className={getQualityColor(quality.audioQuality)}>
              {quality.videoFrameRate}fps
            </span>
          </div>
          
          {quality.audioLevel > 0 && (
            <div className="flex items-center justify-between">
              <span className="text-gray-300">Audio Level:</span>
              <span className={getQualityColor(quality.audioQuality)}>
                {(quality.audioLevel * 100).toFixed(0)}%
              </span>
            </div>
          )}
          
          <div className="flex items-center justify-between">
            <span className="text-gray-300">Packet Loss:</span>
            <span className={getQualityColor(quality.audioQuality)}>
              {(quality.packetLoss * 100).toFixed(1)}%
            </span>
          </div>
        </div>

        {/* Errors */}
        {qualityMetrics.errors && qualityMetrics.errors.length > 0 && (
          <div className="border-t border-gray-700 pt-2">
            <span className="text-red-400 text-xs font-semibold">Issues:</span>
            <div className="text-red-400 text-xs mt-1">
              {qualityMetrics.errors.slice(0, 2).map((error, idx) => (
                <div key={idx}>• {error}</div>
              ))}
            </div>
          </div>
        )}

        {/* Last Updated */}
        <div className="text-gray-500 text-xs pt-1 border-t border-gray-700">
          Updated: {new Date(qualityMetrics.timestamp).toLocaleTimeString()}
        </div>
      </div>
    </div>
  );
}