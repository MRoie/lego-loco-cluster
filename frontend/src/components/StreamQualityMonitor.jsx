import React, { useState, useEffect } from 'react';

/**
 * Stream Quality Monitor Component
 * Displays real-time quality metrics for all instances
 */
export default function StreamQualityMonitor() {
  const [qualityMetrics, setQualityMetrics] = useState({});
  const [summary, setSummary] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);

  // Fetch quality metrics from backend
  const fetchQualityData = async () => {
    try {
      setError(null);
      
      // Fetch both metrics and summary
      const [metricsResponse, summaryResponse] = await Promise.all([
        fetch('/api/quality/metrics'),
        fetch('/api/quality/summary')
      ]);

      if (!metricsResponse.ok || !summaryResponse.ok) {
        throw new Error('Failed to fetch quality data');
      }

      const metrics = await metricsResponse.json();
      const summaryData = await summaryResponse.json();

      setQualityMetrics(metrics);
      setSummary(summaryData);
      setIsLoading(false);
    } catch (err) {
      console.error('Failed to fetch quality data:', err);
      setError(err.message);
      setIsLoading(false);
    }
  };

  // Auto-refresh quality data
  useEffect(() => {
    fetchQualityData();
    
    const interval = setInterval(fetchQualityData, 5000); // Update every 5 seconds
    
    return () => clearInterval(interval);
  }, []);

  // Quality indicator component
  const QualityIndicator = ({ quality, value, unit = '' }) => {
    const getColorClass = () => {
      switch (quality) {
        case 'excellent': return 'text-green-500';
        case 'good': return 'text-blue-500';
        case 'fair': return 'text-yellow-500';
        case 'poor': return 'text-orange-500';
        case 'error':
        case 'unavailable': return 'text-red-500';
        default: return 'text-gray-500';
      }
    };

    return (
      <span className={`font-semibold ${getColorClass()}`}>
        {value}{unit}
      </span>
    );
  };

  // Instance quality row
  const InstanceQualityRow = ({ instanceId, metrics }) => {
    const { availability, quality, timestamp, errors } = metrics;
    
    return (
      <div className="border border-gray-200 rounded-lg p-4 mb-2 bg-white shadow-sm">
        <div className="flex justify-between items-start mb-2">
          <h3 className="font-semibold text-lg">{instanceId}</h3>
          <span className="text-xs text-gray-500">
            {new Date(timestamp).toLocaleTimeString()}
          </span>
        </div>
        
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-2">
          <div>
            <span className="text-sm text-gray-600">VNC Available:</span>
            <br />
            <span className={`font-bold ${availability.vnc ? 'text-green-500' : 'text-red-500'}`}>
              {availability.vnc ? '✓' : '✗'}
            </span>
          </div>
          
          <div>
            <span className="text-sm text-gray-600">Stream Available:</span>
            <br />
            <span className={`font-bold ${availability.stream ? 'text-green-500' : 'text-red-500'}`}>
              {availability.stream ? '✓' : '✗'}
            </span>
          </div>
          
          <div>
            <span className="text-sm text-gray-600">Latency:</span>
            <br />
            <QualityIndicator 
              quality={quality.audioQuality} 
              value={quality.connectionLatency || 'N/A'} 
              unit={quality.connectionLatency ? 'ms' : ''} 
            />
          </div>
          
          <div>
            <span className="text-sm text-gray-600">Frame Rate:</span>
            <br />
            <QualityIndicator 
              quality={quality.audioQuality} 
              value={quality.videoFrameRate || 0} 
              unit="fps" 
            />
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-2">
          <div>
            <span className="text-sm text-gray-600">Audio Quality:</span>
            <br />
            <QualityIndicator quality={quality.audioQuality} value={quality.audioQuality} />
          </div>
          
          <div>
            <span className="text-sm text-gray-600">Packet Loss:</span>
            <br />
            <QualityIndicator 
              quality={quality.audioQuality} 
              value={(quality.packetLoss * 100).toFixed(1)} 
              unit="%" 
            />
          </div>
          
          <div>
            <span className="text-sm text-gray-600">Jitter:</span>
            <br />
            <QualityIndicator 
              quality={quality.audioQuality} 
              value={quality.jitter.toFixed(1)} 
              unit="ms" 
            />
          </div>
        </div>

        {errors && errors.length > 0 && (
          <div className="mt-2 p-2 bg-red-50 border border-red-200 rounded">
            <span className="text-sm text-red-600 font-semibold">Errors:</span>
            <ul className="text-sm text-red-600 mt-1">
              {errors.map((error, idx) => (
                <li key={idx}>• {error}</li>
              ))}
            </ul>
          </div>
        )}
      </div>
    );
  };

  if (isLoading) {
    return (
      <div className="p-6 bg-gray-50 rounded-lg">
        <div className="flex items-center justify-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
          <span className="ml-2">Loading quality metrics...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6 bg-red-50 border border-red-200 rounded-lg">
        <h3 className="text-red-600 font-semibold mb-2">Quality Monitor Error</h3>
        <p className="text-red-600">{error}</p>
        <button 
          onClick={fetchQualityData}
          className="mt-2 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Summary */}
      {summary && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h2 className="text-lg font-semibold text-blue-800 mb-3">Quality Summary</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div>
              <span className="text-sm text-blue-600">Total Instances:</span>
              <br />
              <span className="text-xl font-bold text-blue-800">{summary.total}</span>
            </div>
            <div>
              <span className="text-sm text-blue-600">Available:</span>
              <br />
              <span className="text-xl font-bold text-green-600">{summary.available}</span>
            </div>
            <div>
              <span className="text-sm text-blue-600">Availability:</span>
              <br />
              <span className="text-xl font-bold text-blue-800">
                {summary.availabilityPercent.toFixed(1)}%
              </span>
            </div>
            <div>
              <span className="text-sm text-blue-600">Avg Latency:</span>
              <br />
              <span className="text-xl font-bold text-blue-800">
                {summary.averageLatency ? `${summary.averageLatency}ms` : 'N/A'}
              </span>
            </div>
          </div>
          
          {/* Quality distribution */}
          {Object.keys(summary.qualityDistribution).length > 0 && (
            <div className="mt-3">
              <span className="text-sm text-blue-600">Quality Distribution:</span>
              <div className="flex flex-wrap gap-2 mt-1">
                {Object.entries(summary.qualityDistribution).map(([quality, count]) => (
                  <span 
                    key={quality} 
                    className="px-2 py-1 rounded text-xs bg-blue-100 text-blue-800"
                  >
                    {quality}: {count}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Instance Details */}
      <div>
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-lg font-semibold">Instance Quality Metrics</h2>
          <button 
            onClick={fetchQualityData}
            className="px-3 py-1 bg-blue-600 text-white rounded text-sm hover:bg-blue-700"
          >
            Refresh
          </button>
        </div>
        
        {Object.keys(qualityMetrics).length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            No quality metrics available. The monitoring service may be starting up.
          </div>
        ) : (
          <div>
            {Object.entries(qualityMetrics).map(([instanceId, metrics]) => (
              <InstanceQualityRow 
                key={instanceId} 
                instanceId={instanceId} 
                metrics={metrics} 
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}