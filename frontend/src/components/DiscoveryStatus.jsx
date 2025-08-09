import React, { useEffect, useState } from 'react';
import LoadingSpinner from './LoadingSpinner';

export default function DiscoveryStatus() {
  const [discoveryInfo, setDiscoveryInfo] = useState(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    const fetchDiscoveryInfo = () => {
      fetch('/api/instances/discovery-info')
        .then(r => r.json())
        .then(setDiscoveryInfo)
        .catch(console.error);
    };

    fetchDiscoveryInfo();
    
    // Refresh discovery info every 30 seconds
    const interval = setInterval(fetchDiscoveryInfo, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      const response = await fetch('/api/instances/refresh', {
        method: 'POST'
      });
      const result = await response.json();
      console.log('Discovery refresh result:', result);
      
      // Emit event to trigger instance reload in main app
      window.dispatchEvent(new CustomEvent('discoveryRefreshed', { detail: result }));
      
      // Refresh discovery info after manual refresh
      setTimeout(() => {
        fetch('/api/instances/discovery-info')
          .then(r => r.json())
          .then(setDiscoveryInfo)
          .catch(console.error);
      }, 1000);
      
    } catch (error) {
      console.error('Failed to refresh discovery:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  if (!discoveryInfo) {
    return (
      <div className="flex items-center space-x-2">
        <LoadingSpinner size="sm" variant="secondary" />
        <span className="text-xs text-gray-400">Loading discovery...</span>
      </div>
    );
  }

  const { usingAutoDiscovery, kubernetesDiscovery, fallbackToStatic } = discoveryInfo;

  return (
    <div className="flex items-center space-x-3 text-xs">
      <div className="flex items-center space-x-2">
        <div className={`w-2 h-2 rounded-full ${
          usingAutoDiscovery ? 'bg-green-400' : 'bg-yellow-400'
        }`} />
        <span className="text-gray-300">
          {usingAutoDiscovery ? 'Auto-Discovery' : 'Static Config'}
        </span>
      </div>
      
      {kubernetesDiscovery && (
        <div className="text-gray-400">
          K8s: {kubernetesDiscovery.namespace}
          {kubernetesDiscovery.cachedInstancesCount !== undefined && (
            <span> ({kubernetesDiscovery.cachedInstancesCount} pods)</span>
          )}
        </div>
      )}
      
      {fallbackToStatic && (
        <div className="text-yellow-400">
          Fallback Mode
        </div>
      )}
      
      <button
        onClick={handleRefresh}
        disabled={isRefreshing}
        className={`px-2 py-1 rounded transition-colors ${
          isRefreshing 
            ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
            : 'bg-blue-600 hover:bg-blue-700 text-white'
        }`}
        title="Refresh instance discovery"
      >
        {isRefreshing ? (
          <LoadingSpinner size="sm" variant="light" />
        ) : (
          '🔄'
        )}
      </button>
    </div>
  );
}