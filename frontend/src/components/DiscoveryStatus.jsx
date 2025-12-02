import React, { useState } from 'react';
import { refreshDiscovery } from '../api/discovery';

export default function DiscoveryStatus({ status }) {
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      const result = await refreshDiscovery();
      console.log('Discovery refresh result:', result);

      // Emit event to trigger instance reload in main app
      window.dispatchEvent(new CustomEvent('discoveryRefreshed', { detail: result }));

    } catch (error) {
      console.error('Failed to refresh discovery:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  if (!status) {
    return (
      <div className="text-xs text-gray-400">
        Loading discovery info...
      </div>
    );
  }

  const { mode, stats, lastUpdate, serviceName } = status;
  const isAuto = mode && mode.includes('kubernetes');
  const isEndpoints = mode === 'kubernetes-endpoints';

  return (
    <div className="flex items-center space-x-3 text-xs bg-black/30 p-2 rounded-lg backdrop-blur-sm border border-white/10">
      <div className="flex items-center space-x-2" title={`Mode: ${mode}\nService: ${serviceName || 'N/A'}`}>
        <div className={`w-2 h-2 rounded-full ${isAuto ? 'bg-green-400' : 'bg-yellow-400'
          } ${isRefreshing ? 'animate-pulse' : ''}`} />
        <span className="text-gray-300 font-medium">
          {isEndpoints ? 'Endpoints Discovery' : (isAuto ? 'Pod Discovery' : 'Static Config')}
        </span>
      </div>

      {stats && (
        <div className="text-gray-400 border-l border-gray-600 pl-3 flex space-x-2">
          <span title="Ready Instances" className={stats.ready > 0 ? "text-green-400" : "text-gray-500"}>
            {stats.ready} Ready
          </span>
          <span className="text-gray-600">/</span>
          <span title="Total Instances">
            {stats.total} Total
          </span>
          {stats.notReady > 0 && (
            <span className="text-yellow-400 ml-1">
              ({stats.notReady} Booting)
            </span>
          )}
        </div>
      )}

      <div className="border-l border-gray-600 pl-2">
        <button
          onClick={handleRefresh}
          disabled={isRefreshing}
          className={`p-1 rounded transition-colors ${isRefreshing
              ? 'text-gray-500 cursor-not-allowed'
              : 'text-blue-400 hover:text-blue-300 hover:bg-white/10'
            }`}
          title={`Last update: ${lastUpdate ? new Date(lastUpdate).toLocaleTimeString() : 'Never'}\nClick to refresh`}
        >
          <svg
            className={`w-4 h-4 ${isRefreshing ? 'animate-spin' : ''}`}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      </div>
    </div>
  );
}