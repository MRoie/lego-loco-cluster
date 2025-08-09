import React from 'react';
import { motion } from 'framer-motion';

/**
 * Reusable loading spinner component with LEGO theming
 * Props:
 * - size: 'sm' | 'md' | 'lg' (default: 'md')
 * - message: Optional loading message to display
 * - className: Additional CSS classes
 * - variant: 'primary' | 'secondary' | 'light' (default: 'primary')
 */
export default function LoadingSpinner({ 
  size = 'md', 
  message, 
  className = '', 
  variant = 'primary' 
}) {
  const sizeClasses = {
    sm: 'w-6 h-6',
    md: 'w-10 h-10', 
    lg: 'w-16 h-16'
  };

  const colorClasses = {
    primary: 'border-yellow-400 border-t-red-600',
    secondary: 'border-blue-400 border-t-green-500',
    light: 'border-white/50 border-t-white'
  };

  const textSizeClasses = {
    sm: 'text-xs',
    md: 'text-sm',
    lg: 'text-base'
  };

  const textColorClasses = {
    primary: 'text-yellow-400',
    secondary: 'text-blue-400', 
    light: 'text-white'
  };

  return (
    <div className={`flex flex-col items-center justify-center ${className}`}>
      {/* LEGO-themed spinning loader */}
      <motion.div
        className={`
          ${sizeClasses[size]} 
          border-3 ${colorClasses[variant]} 
          rounded-full shadow-lg
        `}
        animate={{ rotate: 360 }}
        transition={{ 
          repeat: Infinity, 
          duration: 1, 
          ease: "linear" 
        }}
      />
      
      {/* LEGO brick dots overlay for authentic feel */}
      <motion.div
        className={`
          absolute ${sizeClasses[size]}
          flex items-center justify-center
        `}
        animate={{ scale: [1, 1.1, 1] }}
        transition={{ 
          repeat: Infinity, 
          duration: 2, 
          ease: "easeInOut" 
        }}
      >
        <div className="grid grid-cols-2 gap-1">
          {[...Array(4)].map((_, i) => (
            <motion.div
              key={i}
              className={`w-1 h-1 rounded-full ${
                variant === 'light' ? 'bg-white/30' : 'bg-black/20'
              }`}
              animate={{ opacity: [0.3, 1, 0.3] }}
              transition={{ 
                repeat: Infinity, 
                duration: 1.5, 
                delay: i * 0.1,
                ease: "easeInOut" 
              }}
            />
          ))}
        </div>
      </motion.div>

      {/* Loading message */}
      {message && (
        <motion.p 
          className={`
            mt-3 font-bold lego-text tracking-wide
            ${textSizeClasses[size]} 
            ${textColorClasses[variant]}
          `}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
        >
          {message}
        </motion.p>
      )}
    </div>
  );
}