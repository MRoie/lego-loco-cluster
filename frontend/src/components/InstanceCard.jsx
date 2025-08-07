import React from 'react';
import { motion } from 'framer-motion';
import ReactVNCViewer from './ReactVNCViewer';
import useWebRTC from '../hooks/useWebRTC';
import AudioSinkSelector from './AudioSinkSelector';

/**
 * Individual instance card component for the 3x3 grid
 * Props:
 * - instance: instance object with id, status, provisioned, etc.
 * - isActive: whether this card is currently focused
 * - onClick: callback when card is clicked
 */
export default function InstanceCard({ instance, isActive, onClick }) {
  const { videoRef, loading } = useWebRTC(instance.id);
  
  const getStatusColor = (status) => {
    switch (status) {
      case 'ready':
        return 'status-glow-green';
      case 'running':
        return 'status-glow-blue';
      case 'booting':
        return 'status-glow-yellow';
      case 'error':
        return 'status-glow-red';
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

  const getPlaceholderContent = () => {
    if (!instance.provisioned) {
      return {
        icon: '🚫',
        title: 'Not Provisioned',
        subtitle: 'Instance not available',
        bgClass: 'bg-gray-700/30',
        borderClass: 'border-gray-600/50',
        iconBg: 'bg-gray-600/30'
      };
    }
    
    switch (instance.status) {
      case 'booting':
        return {
          icon: '⚡',
          title: 'Booting...',
          subtitle: 'System initialization',
          bgClass: 'bg-yellow-900/20',
          borderClass: 'border-yellow-500/50',
          iconBg: 'bg-yellow-500/20',
          animated: true
        };
      case 'error':
        return {
          icon: '❌',
          title: 'Error',
          subtitle: 'Failed to start',
          bgClass: 'bg-red-900/20',
          borderClass: 'border-red-500/50',
          iconBg: 'bg-red-500/20'
        };
      default:
        return {
          icon: '❓',
          title: 'Unknown Status',
          subtitle: 'Checking connection...',
          bgClass: 'bg-gray-700/20',
          borderClass: 'border-gray-500/50',
          iconBg: 'bg-gray-500/20'
        };
    }
  };

  const placeholder = getPlaceholderContent();

  return (
    <motion.div
      onClick={onClick}
      className={`
        relative rounded-xl transition-all duration-300 cursor-pointer overflow-hidden
        ${isActive 
          ? 'ring-2 ring-blue-400/60 ring-offset-2 ring-offset-transparent card-depth' 
          : 'card-depth-subtle glass-card'
        }
        ${!instance.provisioned ? 'opacity-75' : ''}
      `}
      whileHover={{ scale: 1.02, y: -2 }}
      whileTap={{ scale: 0.98 }}
      layout
    >
      {/* Background with gradient */}
      <div className="absolute inset-0 bg-gradient-to-br from-gray-800/80 to-gray-900/90 backdrop-blur-md" />
      
      {/* Header with instance ID and status */}
      <div className="relative p-4 border-b border-white/10 glass-card">
        <div className="flex items-center justify-between mb-2">
          <h3 className="text-sm font-medium text-white te-mono truncate pr-2">
            {instance.name || instance.id}
          </h3>
          <div className="flex items-center space-x-2 flex-shrink-0">
            <div className={`w-2.5 h-2.5 rounded-full ${getStatusColor(instance.status)}`} />
            <span className="text-xs text-gray-300 te-mono">
              {getStatusText(instance.status, instance.provisioned)}
            </span>
          </div>
        </div>
        {instance.description && (
          <p className="text-xs text-gray-400 truncate te-mono mb-2">{instance.description}</p>
        )}
        <AudioSinkSelector mediaRef={videoRef} />
      </div>

      {/* VNC Content Area */}
      <div className="relative aspect-video bg-black/80 backdrop-blur-sm">
        {instance.provisioned && instance.ready ? (
          <>
            <ReactVNCViewer instanceId={instance.id} />
            <video ref={videoRef} className="hidden" />
            {loading && (
              <motion.div 
                className="absolute inset-0 flex items-center justify-center text-xs text-white bg-black/60 backdrop-blur-sm"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
              >
                <div className="text-center">
                  <motion.div
                    className="w-8 h-8 border-2 border-blue-400 border-t-transparent rounded-full mx-auto mb-2"
                    animate={{ rotate: 360 }}
                    transition={{ repeat: Infinity, duration: 1, ease: "linear" }}
                  />
                  <p className="te-mono">Loading stream...</p>
                </div>
              </motion.div>
            )}
          </>
        ) : (
          <div className={`w-full h-full flex flex-col items-center justify-center text-gray-300 ${placeholder.bgClass} backdrop-blur-sm`}>
            <motion.div 
              className={`w-16 h-16 border-2 ${placeholder.borderClass} rounded-xl mb-3 flex items-center justify-center ${placeholder.iconBg} backdrop-blur-sm`}
              animate={placeholder.animated ? { scale: [1, 1.1, 1] } : {}}
              transition={{ repeat: Infinity, duration: 2, ease: "easeInOut" }}
            >
              <span className="text-2xl">{placeholder.icon}</span>
            </motion.div>
            <p className="text-sm font-medium mb-1 te-mono">{placeholder.title}</p>
            <p className="text-xs opacity-75 te-mono text-center px-4">{placeholder.subtitle}</p>
            
            {instance.status === 'booting' && (
              <div className="w-32 h-1 bg-gray-700/50 rounded-full mt-3 overflow-hidden backdrop-blur-sm">
                <motion.div
                  className="h-full bg-gradient-to-r from-yellow-500 to-orange-500 rounded-full"
                  animate={{ x: ['-100%', '100%'] }}
                  transition={{ repeat: Infinity, duration: 1.5, ease: "easeInOut" }}
                />
              </div>
            )}
          </div>
        )}
      </div>

      {/* Active indicator overlay */}
      {isActive && (
        <motion.div
          className="absolute inset-0 border-2 border-blue-400/60 rounded-xl pointer-events-none"
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          layoutId="activeCardBorder"
        />
      )}
      
      {/* Subtle glow effect for active card */}
      {isActive && (
        <motion.div
          className="absolute inset-0 bg-blue-400/5 rounded-xl pointer-events-none"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
        />
      )}
    </motion.div>
  );
}
