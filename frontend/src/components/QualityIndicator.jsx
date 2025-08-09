import React, { useState, useEffect } from 'react';

/**
 * Quality Indicator Component for Individual Instance Cards
 * Shows real-time quality metrics for a specific instance with deep health information
 */
export default function QualityIndicator({ instanceId, compact = false }) {
  const [qualityMetrics, setQualityMetrics] = useState(null);
  const [deepHealth, setDeepHealth] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showDetails, setShowDetails] = useState(false);
  const [isRecovering, setIsRecovering] = useState(false);

  // Fetch quality metrics for this specific instance
  const fetchInstanceQuality = async () => {
    try {
      const [qualityResponse, deepHealthResponse] = await Promise.all([
        fetch(`/api/quality/metrics/${instanceId}`),
        fetch(`/api/quality/deep-health/${instanceId}`)
      ]);
      
      if (qualityResponse.ok) {
        const metrics = await qualityResponse.json();
        setQualityMetrics(metrics);
      }
      
      if (deepHealthResponse.ok) {
        const health = await deepHealthResponse.json();
        setDeepHealth(health);
      }
      
      setError(null);
      setIsLoading(false);
    } catch (err) {
      console.error(`Failed to fetch quality for ${instanceId}:`, err);
      setError(err.message);
      setIsLoading(false);
    }
  };

  // Trigger recovery for this instance
  const triggerRecovery = async () => {
    setIsRecovering(true);
    try {
      const response = await fetch(`/api/quality/recover/${instanceId}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ forceRecovery: true })
      });
      
      if (response.ok) {
        console.log(`Recovery triggered for ${instanceId}`);
        // Refresh data after a short delay
        setTimeout(fetchInstanceQuality, 2000);
      } else {
        console.error(`Recovery failed for ${instanceId}`);
      }
    } catch (err) {
      console.error(`Recovery error for ${instanceId}:`, err);
    } finally {
      setIsRecovering(false);
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

        {/* Deep Health Status */}
        {deepHealth && (
          <div className="flex items-center justify-between">
            <span className="text-gray-300">QEMU:</span>
            <span className={
              deepHealth.overallStatus === 'healthy' ? 'text-green-400' :
              deepHealth.overallStatus === 'degraded' ? 'text-yellow-400' : 'text-red-400'
            }>
              {deepHealth.overallStatus === 'healthy' ? '✓' :
               deepHealth.overallStatus === 'degraded' ? '⚠' : '✗'}
            </span>
          </div>
        )}

        {/* Recovery Button */}
        {deepHealth && deepHealth.recoveryNeeded && (
          <div className="flex items-center justify-center mt-1">
            <button 
              onClick={triggerRecovery}
              disabled={isRecovering}
              className="px-2 py-1 text-xs bg-orange-600 hover:bg-orange-500 disabled:bg-gray-600 
                         text-white rounded transition-colors duration-200"
            >
              {isRecovering ? '🔄' : '🔧'} {isRecovering ? 'Recovering...' : 'Recover'}
            </button>
          </div>
        )}

        {/* Details Toggle */}
        <div className="flex items-center justify-center mt-1">
          <button 
            onClick={() => setShowDetails(!showDetails)}
            className="text-xs text-blue-400 hover:text-blue-300 transition-colors duration-200"
          >
            {showDetails ? '▲ Less' : '▼ Details'}
          </button>
        </div>

        {/* Detailed Information */}
        {showDetails && deepHealth && (
          <div className="mt-2 pt-2 border-t border-gray-600 space-y-1">
            <div className="text-xs text-gray-400 font-semibold">Deep Health:</div>
            
            {deepHealth.deepHealth && (
              <>
                {/* Video Health */}
                {deepHealth.deepHealth.video && (
                  <div className="flex items-center justify-between">
                    <span className="text-gray-300">Video FPS:</span>
                    <span className="text-blue-400">
                      {deepHealth.deepHealth.video.estimated_frame_rate || 0}
                    </span>
                  </div>
                )}
                
                {/* Audio Health */}
                {deepHealth.deepHealth.audio && (
                  <div className="flex items-center justify-between">
                    <span className="text-gray-300">Audio Devices:</span>
                    <span className="text-blue-400">
                      {deepHealth.deepHealth.audio.audio_devices || 0}
                    </span>
                  </div>
                )}
                
                {/* Performance */}
                {deepHealth.deepHealth.performance && (
                  <>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">CPU:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.performance.qemu_cpu || 0}%
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">Memory:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.performance.qemu_memory || 0}%
                      </span>
                    </div>
                  </>
                )}
              </>
            )}
            
            {/* Failure Type */}
            {deepHealth.failureType && deepHealth.failureType !== 'none' && (
              <div className="flex items-center justify-between">
                <span className="text-gray-300">Issue:</span>
                <span className="text-red-400 capitalize">
                  {deepHealth.failureType}
                </span>
              </div>
            )}
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

        {/* Deep Health Information */}
        {deepHealth && (
          <div className="border-t border-gray-700 pt-2 space-y-1">
            <div className="flex items-center justify-between mb-1">
              <span className="text-blue-400 text-xs font-semibold">QEMU Health:</span>
              <span className={
                deepHealth.overallStatus === 'healthy' ? 'text-green-400' :
                deepHealth.overallStatus === 'degraded' ? 'text-yellow-400' : 'text-red-400'
              }>
                {deepHealth.overallStatus}
              </span>
            </div>
            
            {deepHealth.deepHealth && (
              <>
                {/* Video Subsystem */}
                {deepHealth.deepHealth.video && (
                  <>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">Display Active:</span>
                      <span className={deepHealth.deepHealth.video.display_active ? 'text-green-400' : 'text-red-400'}>
                        {deepHealth.deepHealth.video.display_active ? 'Yes' : 'No'}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">Estimated FPS:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.video.estimated_frame_rate || 0}
                      </span>
                    </div>
                  </>
                )}
                
                {/* Audio Subsystem */}
                {deepHealth.deepHealth.audio && (
                  <>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">PulseAudio:</span>
                      <span className={deepHealth.deepHealth.audio.pulse_running ? 'text-green-400' : 'text-red-400'}>
                        {deepHealth.deepHealth.audio.pulse_running ? 'Running' : 'Stopped'}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">Audio Devices:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.audio.audio_devices || 0}
                      </span>
                    </div>
                  </>
                )}
                
                {/* Performance */}
                {deepHealth.deepHealth.performance && (
                  <>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">QEMU CPU:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.performance.qemu_cpu || 0}%
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">QEMU Memory:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.performance.qemu_memory || 0}%
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">System Load:</span>
                      <span className="text-blue-400">
                        {deepHealth.deepHealth.performance.load_average || 0}
                      </span>
                    </div>
                  </>
                )}
                
                {/* Network Health */}
                {deepHealth.deepHealth.network && (
                  <>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-300">Bridge/TAP:</span>
                      <span className={
                        deepHealth.deepHealth.network.bridge_up && deepHealth.deepHealth.network.tap_up ? 
                        'text-green-400' : 'text-red-400'
                      }>
                        {deepHealth.deepHealth.network.bridge_up && deepHealth.deepHealth.network.tap_up ? 'Up' : 'Down'}
                      </span>
                    </div>
                    {(deepHealth.deepHealth.network.tx_errors > 0 || deepHealth.deepHealth.network.rx_errors > 0) && (
                      <div className="flex items-center justify-between">
                        <span className="text-gray-300">Network Errors:</span>
                        <span className="text-yellow-400">
                          TX: {deepHealth.deepHealth.network.tx_errors}, RX: {deepHealth.deepHealth.network.rx_errors}
                        </span>
                      </div>
                    )}
                  </>
                )}
              </>
            )}
            
            {/* Failure Analysis */}
            {deepHealth.failureType && deepHealth.failureType !== 'none' && (
              <div className="flex items-center justify-between">
                <span className="text-gray-300">Issue Type:</span>
                <span className="text-red-400 capitalize">
                  {deepHealth.failureType}
                </span>
              </div>
            )}
            
            {/* Recovery Button */}
            {deepHealth.recoveryNeeded && (
              <div className="flex items-center justify-center mt-2">
                <button 
                  onClick={triggerRecovery}
                  disabled={isRecovering}
                  className="px-3 py-1 text-sm bg-orange-600 hover:bg-orange-500 disabled:bg-gray-600 
                             text-white rounded transition-colors duration-200"
                >
                  {isRecovering ? '🔄 Recovering...' : '🔧 Trigger Recovery'}
                </button>
              </div>
            )}
          </div>
        )}

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