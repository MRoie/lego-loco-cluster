import React from 'react';
import { motion } from 'framer-motion';
import ReactVNCViewer from './ReactVNCViewer';
import useWebRTC from '../hooks/useWebRTC';
import AudioSinkSelector from './AudioSinkSelector';

/**
 * Individual instance card component for the 3x3 grid
 * Styled to match LEGO Loco character cards with red borders, yellow accents, and cream backgrounds
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
        return 'lego-status-ready';
      case 'running':
        return 'lego-status-running';
      case 'booting':
        return 'lego-status-booting';
      case 'error':
        return 'lego-status-error';
      default:
        return 'lego-status-unknown';
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
        bgClass: 'bg-red-100',
        textClass: 'text-red-800',
        iconBg: 'bg-red-200 border-red-400'
      };
    }
    
    switch (instance.status) {
      case 'booting':
        return {
          icon: '⚡',
          title: 'Booting...',
          subtitle: 'System initialization',
          bgClass: 'bg-yellow-100',
          textClass: 'text-yellow-800',
          iconBg: 'bg-yellow-200 border-yellow-400',
          animated: true
        };
      case 'error':
        return {
          icon: '❌',
          title: 'Error',
          subtitle: 'Failed to start',
          bgClass: 'bg-red-100',
          textClass: 'text-red-800',
          iconBg: 'bg-red-200 border-red-400'
        };
      default:
        return {
          icon: '❓',
          title: 'Unknown Status',
          subtitle: 'Checking connection...',
          bgClass: 'bg-gray-100',
          textClass: 'text-gray-800',
          iconBg: 'bg-gray-200 border-gray-400'
        };
    }
  };

  const placeholder = getPlaceholderContent();

  return (
    <motion.div
      onClick={onClick}
      className={`
        relative transition-all duration-300 cursor-pointer overflow-hidden
        ${isActive 
          ? 'lego-card ring-4 ring-blue-400 ring-offset-2 ring-offset-green-500' 
          : 'lego-card'
        }
        ${!instance.provisioned ? 'opacity-90' : ''}
      `}
      whileHover={{ scale: 1.02, y: -2 }}
      whileTap={{ scale: 0.98 }}
      layout
    >
      {/* Header with instance ID and status - styled like LEGO character card header */}
      <div className="relative p-3 bg-yellow-50 border-b-2 border-yellow-400">
        <div className="flex items-center justify-between mb-2">
          <h3 className="text-sm font-bold text-black lego-text truncate pr-2">
            {instance.name || instance.id}
          </h3>
          <div className="flex items-center space-x-2 flex-shrink-0">
            <div className={`w-3 h-3 rounded-sm ${getStatusColor(instance.status)}`} />
            <span className="text-xs text-black lego-text font-semibold">
              {getStatusText(instance.status, instance.provisioned)}
            </span>
          </div>
        </div>
        {instance.description && (
          <p className="text-xs text-gray-700 truncate lego-text mb-2 font-medium">{instance.description}</p>
        )}
        
        {/* LEGO-style control buttons */}
        <div className="flex justify-between items-center">
          <AudioSinkSelector mediaRef={videoRef} />
          <div className="flex space-x-1">
            <button className="w-6 h-6 bg-red-500 border-2 border-red-600 rounded text-white text-xs font-bold flex items-center justify-center hover:bg-red-400 transition-colors">
              ×
            </button>
            <button className="w-6 h-6 bg-blue-500 border-2 border-blue-600 rounded text-white text-xs font-bold flex items-center justify-center hover:bg-blue-400 transition-colors">
              ?
            </button>
          </div>
        </div>
      </div>

      {/* VNC Content Area - styled like the character portrait area */}
      <div className="relative aspect-video lego-stream-area">
        {instance.provisioned && instance.ready ? (
          <>
            <ReactVNCViewer instanceId={instance.id} />
            <video ref={videoRef} className="hidden" />
            {loading && (
              <motion.div 
                className="absolute inset-0 flex items-center justify-center text-sm text-white bg-black/80"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
              >
                <div className="text-center">
                  <motion.div
                    className="w-10 h-10 border-3 border-yellow-400 border-t-transparent rounded-full mx-auto mb-3"
                    animate={{ rotate: 360 }}
                    transition={{ repeat: Infinity, duration: 1, ease: "linear" }}
                  />
                  <p className="lego-text font-bold text-yellow-400">Loading stream...</p>
                </div>
              </motion.div>
            )}
          </>
        ) : (
          <div className={`w-full h-full flex flex-col items-center justify-center ${placeholder.bgClass}`}>
            <motion.div 
              className={`w-16 h-16 border-3 ${placeholder.iconBg} rounded-lg mb-3 flex items-center justify-center`}
              animate={placeholder.animated ? { scale: [1, 1.1, 1] } : {}}
              transition={{ repeat: Infinity, duration: 2, ease: "easeInOut" }}
            >
              <span className="text-2xl">{placeholder.icon}</span>
            </motion.div>
            <p className={`text-sm font-bold mb-1 lego-text ${placeholder.textClass}`}>{placeholder.title}</p>
            <p className={`text-xs lego-text text-center px-4 ${placeholder.textClass} opacity-80`}>{placeholder.subtitle}</p>
            
            {instance.status === 'booting' && (
              <div className="w-32 h-2 lego-progress mt-3">
                <motion.div
                  className="lego-progress-bar"
                  animate={{ x: ['-100%', '100%'] }}
                  transition={{ repeat: Infinity, duration: 1.5, ease: "easeInOut" }}
                />
              </div>
            )}
          </div>
        )}
      </div>

      {/* Active indicator overlay - enhanced for LEGO style */}
      {isActive && (
        <motion.div
          className="absolute inset-0 border-4 border-blue-400 rounded-lg pointer-events-none"
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          layoutId="activeCardBorder"
          style={{
            boxShadow: '0 0 0 2px #FFD700, 0 0 20px rgba(0, 85, 191, 0.5)'
          }}
        />
      )}
      
      {/* LEGO-style glow effect for active card */}
      {isActive && (
        <motion.div
          className="absolute inset-0 bg-blue-400/10 rounded-lg pointer-events-none"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
        />
      )}
    </motion.div>
  );
}
