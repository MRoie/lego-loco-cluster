import React from 'react';
import { motion } from 'framer-motion';
import ReactVNCViewer from './ReactVNCViewer';

/**
 * Individual instance card component for the 3x3 grid
 * Props:
 * - instance: instance object with id, status, provisioned, etc.
 * - isActive: whether this card is currently focused
 * - onClick: callback when card is clicked
 */
export default function InstanceCard({ instance, isActive, onClick }) {
  const getStatusColor = (status) => {
    switch (status) {
      case 'ready':
        return 'bg-green-500';
      case 'running':
        return 'bg-blue-500';
      case 'booting':
        return 'bg-yellow-500';
      case 'error':
        return 'bg-red-500';
      default:
        return 'bg-gray-500';
    }
  };

  const getStatusText = (status, provisioned) => {
    if (!provisioned) return 'Not Provisioned';
    switch (status) {
      case 'ready':
        return 'Ready';
      case 'running':
        return 'Running';
      case 'booting':
        return 'Booting...';
      case 'error':
        return 'Error';
      default:
        return 'Unknown';
    }
  };

  return (
    <motion.div
      onClick={onClick}
      className={`
        relative bg-gray-800 rounded-lg border-2 transition-all duration-200 cursor-pointer
        ${isActive ? 'border-blue-400 ring-2 ring-blue-400/50' : 'border-gray-600 hover:border-gray-500'}
        ${!instance.provisioned ? 'opacity-50' : ''}
      `}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      layout
    >
      {/* Header with instance ID and status */}
      <div className="p-3 border-b border-gray-700">
        <div className="flex items-center justify-between mb-1">
          <h3 className="text-sm font-medium text-white">{instance.name || instance.id}</h3>
          <div className="flex items-center space-x-2">
            <div className={`w-2 h-2 rounded-full ${getStatusColor(instance.status)}`} />
            <span className="text-xs text-gray-300">
              {getStatusText(instance.status, instance.provisioned)}
            </span>
          </div>
        </div>
        {instance.description && (
          <p className="text-xs text-gray-400 truncate">{instance.description}</p>
        )}
      </div>

      {/* VNC Content Area */}
      <div className="aspect-video bg-black rounded-b-lg overflow-hidden">
        {instance.provisioned && instance.ready ? (
          <ReactVNCViewer instanceId={instance.id} />
        ) : (
          <div className="w-full h-full flex flex-col items-center justify-center text-gray-400">
            {!instance.provisioned ? (
              <>
                <div className="w-12 h-12 border-2 border-gray-600 rounded-lg mb-2 flex items-center justify-center">
                  <span className="text-xl">🚫</span>
                </div>
                <p className="text-sm">Not Provisioned</p>
                <p className="text-xs opacity-75">Instance not available</p>
              </>
            ) : instance.status === 'booting' ? (
              <>
                <div className="w-12 h-12 border-2 border-yellow-500 rounded-lg mb-2 flex items-center justify-center animate-pulse">
                  <span className="text-xl">⚡</span>
                </div>
                <p className="text-sm">Booting...</p>
                <div className="w-24 h-1 bg-gray-700 rounded-full mt-2 overflow-hidden">
                  <motion.div
                    className="h-full bg-yellow-500"
                    animate={{ x: ['0%', '100%'] }}
                    transition={{ repeat: Infinity, duration: 1.5 }}
                  />
                </div>
              </>
            ) : instance.status === 'error' ? (
              <>
                <div className="w-12 h-12 border-2 border-red-500 rounded-lg mb-2 flex items-center justify-center">
                  <span className="text-xl">❌</span>
                </div>
                <p className="text-sm">Error</p>
                <p className="text-xs opacity-75">Instance failed to start</p>
              </>
            ) : (
              <>
                <div className="w-12 h-12 border-2 border-gray-500 rounded-lg mb-2 flex items-center justify-center">
                  <span className="text-xl">❓</span>
                </div>
                <p className="text-sm">Unknown Status</p>
              </>
            )}
          </div>
        )}
      </div>

      {/* Active indicator */}
      {isActive && (
        <motion.div
          className="absolute inset-0 border-2 border-blue-400 rounded-lg pointer-events-none"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          layoutId="activeCard"
        />
      )}
    </motion.div>
  );
}
