import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import LoadingSpinner from './LoadingSpinner';

/**
 * Full-screen loading overlay for initial app load
 * Shows progressive loading stages with LEGO theming
 */
export default function AppLoadingOverlay({ 
  isVisible,
  loadingStates,
  isCriticalDataLoaded,
  errors 
}) {
  if (!isVisible) return null;

  const getLoadingMessage = () => {
    if (errors.instances || errors.provisionedInstances) {
      return "Connection issues - retrying...";
    }
    
    if (loadingStates.instances || loadingStates.provisionedInstances) {
      return "Loading LEGO Loco instances...";
    }
    
    if (loadingStates.hotkeys || loadingStates.status) {
      return "Loading configuration...";
    }
    
    return "Almost ready!";
  };

  const getProgressPercentage = () => {
    const totalSteps = 4; // instances, provisionedInstances, hotkeys, status
    const completedSteps = Object.entries(loadingStates)
      .filter(([key, loading]) => key !== 'initialLoad' && !loading)
      .length;
    return Math.round((completedSteps / totalSteps) * 100);
  };

  const hasErrors = errors.instances || errors.provisionedInstances;

  return (
    <AnimatePresence>
      <motion.div
        className="fixed inset-0 bg-gradient-to-br from-green-600 via-green-500 to-blue-600 z-50 flex items-center justify-center"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        transition={{ duration: 0.3 }}
      >
        {/* LEGO-style background pattern */}
        <div className="absolute inset-0 opacity-10">
          <div className="grid grid-cols-20 grid-rows-20 h-full w-full">
            {Array(400).fill(0).map((_, i) => (
              <motion.div 
                key={i} 
                className="border border-white/20"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: i * 0.001 }}
              />
            ))}
          </div>
        </div>

        {/* Main loading content */}
        <motion.div
          className="relative z-10 text-center max-w-md mx-auto px-6"
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.2, duration: 0.5 }}
        >
          {/* LEGO Loco Logo/Title */}
          <motion.div
            className="mb-8"
            animate={{ y: [0, -5, 0] }}
            transition={{ repeat: Infinity, duration: 3, ease: "easeInOut" }}
          >
            <h1 className="text-4xl font-bold text-white lego-text tracking-wider mb-2">
              🚂 LEGO LOCO
            </h1>
            <h2 className="text-xl text-yellow-200 lego-text">
              Cluster Dashboard
            </h2>
          </motion.div>

          {/* Loading spinner */}
          <div className="mb-6">
            <LoadingSpinner 
              size="lg" 
              message={getLoadingMessage()}
              variant="light"
            />
          </div>

          {/* Progress bar */}
          <div className="mb-6">
            <div className="w-full h-4 bg-white/20 rounded-lg overflow-hidden shadow-inner">
              <motion.div
                className={`h-full rounded-lg ${
                  hasErrors 
                    ? 'bg-gradient-to-r from-red-400 to-red-500' 
                    : 'bg-gradient-to-r from-yellow-400 to-yellow-500'
                }`}
                initial={{ width: 0 }}
                animate={{ width: `${getProgressPercentage()}%` }}
                transition={{ duration: 0.5, ease: "easeOut" }}
              />
            </div>
            <p className="text-sm text-white/80 mt-2 lego-text">
              {getProgressPercentage()}% Complete
            </p>
          </div>

          {/* Loading steps indicator */}
          <div className="grid grid-cols-2 gap-3 text-xs">
            {[
              { key: 'instances', label: 'Instances', icon: '🎮' },
              { key: 'provisionedInstances', label: 'Ready Nodes', icon: '✅' },
              { key: 'hotkeys', label: 'Controls', icon: '⌨️' },
              { key: 'status', label: 'Status', icon: '📊' }
            ].map(({ key, label, icon }) => (
              <motion.div
                key={key}
                className={`
                  flex items-center space-x-2 p-2 rounded-lg
                  ${!loadingStates[key] 
                    ? 'bg-green-500/30 text-white' 
                    : errors[key]
                      ? 'bg-red-500/30 text-red-200'
                      : 'bg-white/10 text-white/70'
                  }
                `}
                initial={{ x: -20, opacity: 0 }}
                animate={{ x: 0, opacity: 1 }}
                transition={{ delay: 0.4 + (Object.keys(loadingStates).indexOf(key) * 0.1) }}
              >
                <span className="text-sm">{icon}</span>
                <span className="lego-text font-bold">{label}</span>
                {!loadingStates[key] && !errors[key] && (
                  <motion.span
                    className="text-green-300"
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{ type: "spring", stiffness: 200 }}
                  >
                    ✓
                  </motion.span>
                )}
                {errors[key] && (
                  <motion.span
                    className="text-red-300"
                    animate={{ rotate: [0, 10, -10, 0] }}
                    transition={{ repeat: Infinity, duration: 2 }}
                  >
                    ⚠️
                  </motion.span>
                )}
              </motion.div>
            ))}
          </div>

          {/* Error message */}
          {hasErrors && (
            <motion.div
              className="mt-6 p-4 bg-red-500/20 border border-red-400/30 rounded-lg"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
            >
              <p className="text-red-200 text-sm lego-text">
                ⚠️ Some data couldn't be loaded. The app will work with limited functionality.
              </p>
            </motion.div>
          )}
        </motion.div>

        {/* LEGO brick decorations */}
        {Array(6).fill(0).map((_, i) => (
          <motion.div
            key={i}
            className="absolute w-8 h-8 bg-white/10 rounded border-2 border-white/20"
            style={{
              left: `${10 + i * 15}%`,
              top: `${20 + (i % 2) * 60}%`,
            }}
            animate={{ 
              y: [0, -10, 0],
              rotate: [0, 180, 360] 
            }}
            transition={{ 
              repeat: Infinity, 
              duration: 4 + i, 
              ease: "easeInOut" 
            }}
          >
            <div className="grid grid-cols-2 gap-1 p-1">
              {Array(4).fill(0).map((_, j) => (
                <div key={j} className="w-1 h-1 bg-white/30 rounded-full" />
              ))}
            </div>
          </motion.div>
        ))}
      </motion.div>
    </AnimatePresence>
  );
}