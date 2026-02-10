import React, { useEffect, useState, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

/**
 * Live Benchmark Overlay
 * Shows real-time performance metrics for all emulator instances
 * Polls /api/benchmark/live every 3 seconds
 */
export default function BenchmarkOverlay({ visible = true, onToggle }) {
  const [metrics, setMetrics] = useState(null);
  const [history, setHistory] = useState([]);
  const [collapsed, setCollapsed] = useState(false);
  const intervalRef = useRef(null);

  useEffect(() => {
    if (!visible) return;

    const fetchMetrics = async () => {
      try {
        const res = await fetch('/api/benchmark/live');
        if (res.ok) {
          const data = await res.json();
          setMetrics(data);
          setHistory(prev => [...prev.slice(-59), { ...data, ts: Date.now() }]);
        }
      } catch (e) {
        console.error('Benchmark fetch failed:', e);
      }
    };

    fetchMetrics();
    intervalRef.current = setInterval(fetchMetrics, 3000);
    return () => clearInterval(intervalRef.current);
  }, [visible]);

  if (!visible || !metrics) return null;

  const { instances = [], summary = {} } = metrics;

  const getStatusColor = (val, thresholds) => {
    if (val >= thresholds.good) return 'text-green-400';
    if (val >= thresholds.warn) return 'text-yellow-400';
    return 'text-red-400';
  };

  const getFpsColor = (fps) => getStatusColor(fps, { good: 20, warn: 10 });
  const getLatColor = (lat) => {
    if (lat <= 100) return 'text-green-400';
    if (lat <= 200) return 'text-yellow-400';
    return 'text-red-400';
  };
  const getCpuColor = (cpu) => {
    if (cpu <= 50) return 'text-green-400';
    if (cpu <= 75) return 'text-yellow-400';
    return 'text-red-400';
  };

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -20 }}
        className="fixed top-0 left-0 right-0 z-50 pointer-events-none"
      >
        <div className="pointer-events-auto mx-auto max-w-7xl px-4 pt-2">
          {/* Toggle bar */}
          <div className="flex justify-between items-center bg-black/80 backdrop-blur-sm rounded-t-lg px-4 py-1 border border-green-500/30">
            <div className="flex items-center space-x-3">
              <div className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
              <span className="text-green-400 font-mono text-xs font-bold tracking-wider">
                LIVE BENCHMARK
              </span>
              <span className="text-gray-400 font-mono text-xs">
                {instances.length} instances | {summary.networkMode || 'socket'} LAN
              </span>
            </div>
            <div className="flex items-center space-x-2">
              <span className={`font-mono text-xs font-bold ${summary.allHealthy ? 'text-green-400' : 'text-red-400'}`}>
                {summary.allHealthy ? '● ALL HEALTHY' : '● DEGRADED'}
              </span>
              <button
                onClick={() => setCollapsed(!collapsed)}
                className="text-gray-400 hover:text-white text-sm px-2"
              >
                {collapsed ? '▼' : '▲'}
              </button>
              {onToggle && (
                <button onClick={onToggle} className="text-gray-400 hover:text-red-400 text-sm px-1">✕</button>
              )}
            </div>
          </div>

          {/* Metrics table */}
          {!collapsed && (
            <motion.div
              initial={{ height: 0 }}
              animate={{ height: 'auto' }}
              exit={{ height: 0 }}
              className="bg-black/85 backdrop-blur-sm border-x border-b border-green-500/30 rounded-b-lg overflow-hidden"
            >
              {/* Header row */}
              <div className="grid grid-cols-9 gap-1 px-3 py-1 text-[10px] font-mono text-gray-500 border-b border-gray-700/50">
                <span>INSTANCE</span>
                <span>STATUS</span>
                <span>FPS</span>
                <span>LATENCY</span>
                <span>CPU</span>
                <span>MEM</span>
                <span>QEMU</span>
                <span>DISPLAY</span>
                <span>NETWORK</span>
              </div>

              {/* Instance rows */}
              {instances.map((inst, i) => (
                <div
                  key={inst.id || i}
                  className="grid grid-cols-9 gap-1 px-3 py-0.5 text-[11px] font-mono border-b border-gray-800/50 hover:bg-green-900/10"
                >
                  <span className="text-blue-300 truncate" title={inst.id}>
                    emu-{inst.instanceId ?? i}
                  </span>
                  <span className={inst.healthy ? 'text-green-400' : 'text-red-400'}>
                    {inst.healthy ? 'OK' : 'ERR'}
                  </span>
                  <span className={getFpsColor(inst.fps || 0)}>
                    {inst.fps || 0}
                  </span>
                  <span className={getLatColor(inst.latency || 0)}>
                    {inst.latency ? `${inst.latency.toFixed(0)}ms` : '--'}
                  </span>
                  <span className={getCpuColor(inst.cpu || 0)}>
                    {inst.cpu ? `${inst.cpu.toFixed(1)}%` : '--'}
                  </span>
                  <span className="text-gray-300">
                    {inst.memory ? `${inst.memory.toFixed(1)}%` : '--'}
                  </span>
                  <span>{inst.qemuHealthy ? '✅' : '❌'}</span>
                  <span>{inst.displayActive ? '✅' : '❌'}</span>
                  <span>{inst.networkOk ? '✅' : '❌'}</span>
                </div>
              ))}

              {/* Summary row */}
              <div className="grid grid-cols-9 gap-1 px-3 py-1 text-[11px] font-mono bg-gray-900/60 border-t border-green-500/20">
                <span className="text-white font-bold">TOTAL</span>
                <span className="text-gray-400">{summary.healthyCount || 0}/{instances.length}</span>
                <span className={getFpsColor(summary.avgFps || 0)}>
                  avg {summary.avgFps || 0}
                </span>
                <span className={getLatColor(summary.avgLatency || 0)}>
                  avg {summary.avgLatency ? `${summary.avgLatency.toFixed(0)}ms` : '--'}
                </span>
                <span className={getCpuColor(summary.avgCpu || 0)}>
                  avg {summary.avgCpu ? `${summary.avgCpu.toFixed(1)}%` : '--'}
                </span>
                <span className="text-gray-300">
                  avg {summary.avgMemory ? `${summary.avgMemory.toFixed(1)}%` : '--'}
                </span>
                <span colSpan={3} className="text-gray-500">
                  {new Date().toLocaleTimeString()}
                </span>
                <span />
                <span />
              </div>

              {/* Pass/fail criteria bar */}
              <div className="flex items-center space-x-4 px-3 py-1 bg-gray-900/80 text-[10px] font-mono">
                <span className="text-gray-500">GATES:</span>
                <span className={summary.avgFps >= 15 ? 'text-green-400' : 'text-red-400'}>
                  FPS≥15 {summary.avgFps >= 15 ? '✓' : '✗'}
                </span>
                <span className={(summary.avgLatency || 0) <= 250 ? 'text-green-400' : 'text-red-400'}>
                  LAT≤250ms {(summary.avgLatency || 0) <= 250 ? '✓' : '✗'}
                </span>
                <span className={(summary.avgCpu || 0) <= 80 ? 'text-green-400' : 'text-red-400'}>
                  CPU≤80% {(summary.avgCpu || 0) <= 80 ? '✓' : '✗'}
                </span>
                <span className={summary.allHealthy ? 'text-green-400' : 'text-red-400'}>
                  LAN {summary.allHealthy ? '✓' : '✗'}
                </span>
              </div>
            </motion.div>
          )}
        </div>
      </motion.div>
    </AnimatePresence>
  );
}
