import React, { useState } from 'react';
import { refreshDiscovery } from '../api/discovery';

const TOTAL_SLOTS = 9;

const STATE_CONFIG = {
  ready:       { label: 'Streaming', color: 'bg-green-500',  text: 'text-green-400', ring: 'ring-green-400/40' },
  running:     { label: 'Streaming', color: 'bg-green-500',  text: 'text-green-400', ring: 'ring-green-400/40' },
  connecting:  { label: 'Connecting', color: 'bg-yellow-400', text: 'text-yellow-300', ring: 'ring-yellow-400/40' },
  booting:     { label: 'Connecting', color: 'bg-yellow-400', text: 'text-yellow-300', ring: 'ring-yellow-400/40' },
  degraded:    { label: 'Degraded',  color: 'bg-orange-500', text: 'text-orange-400', ring: 'ring-orange-400/40' },
  error:       { label: 'Error',     color: 'bg-red-500',    text: 'text-red-400',    ring: 'ring-red-500/40' },
  offline:     { label: 'Offline',   color: 'bg-gray-500',   text: 'text-gray-400',   ring: 'ring-gray-500/40' },
  unknown:     { label: 'Unknown',   color: 'bg-gray-500',   text: 'text-gray-400',   ring: 'ring-gray-500/40' },
};

function stateFor(status) {
  return STATE_CONFIG[status] || STATE_CONFIG.unknown;
}

function InstanceDot({ instance }) {
  const cfg = stateFor(instance.status);
  const name = instance.name || instance.hostname || instance.id;
  return (
    <div
      className={`w-5 h-5 rounded-full ${cfg.color} ring-2 ${cfg.ring} flex items-center justify-center cursor-default transition-transform hover:scale-125`}
      title={`${name} — ${cfg.label}`}
    >
      <span className="text-[8px] font-bold text-white leading-none select-none">
        {name.charAt(0).toUpperCase()}
      </span>
    </div>
  );
}

function EmptyDot() {
  return (
    <div
      className="w-5 h-5 rounded-full border-2 border-dashed border-gray-600 cursor-default"
      title="Empty slot"
    />
  );
}

export default function DiscoveryStatus({ status }) {
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      const result = await refreshDiscovery();
      window.dispatchEvent(new CustomEvent('discoveryRefreshed', { detail: result }));
    } catch (error) {
      console.error('Failed to refresh discovery:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  if (!status) {
    return (
      <div className="flex items-center space-x-2 text-xs text-gray-400 bg-black/30 px-3 py-2 rounded-lg border border-white/10">
        <div className="w-3 h-3 rounded-full bg-gray-600 animate-pulse" />
        <span>Discovering instances…</span>
      </div>
    );
  }

  const { mode, stats, lastUpdate, serviceName, instances = [] } = status;
  const discovered = stats?.total ?? instances.length;
  const ready = stats?.ready ?? 0;
  const pct = Math.round((discovered / TOTAL_SLOTS) * 100);
  const isAuto = mode && mode.includes('kubernetes');

  return (
    <div className="text-xs bg-black/30 rounded-lg backdrop-blur-sm border border-white/10 select-none">
      {/* Compact bar — always visible */}
      <button
        type="button"
        onClick={() => setExpanded(e => !e)}
        className="flex items-center space-x-3 px-3 py-2 w-full text-left"
      >
        {/* Discovery mode dot */}
        <div
          className={`w-2 h-2 rounded-full flex-shrink-0 ${isAuto ? 'bg-green-400' : 'bg-yellow-400'} ${isRefreshing ? 'animate-pulse' : ''}`}
          title={`Mode: ${mode}\nService: ${serviceName || 'N/A'}`}
        />

        {/* Count label */}
        <span className="text-gray-200 font-semibold whitespace-nowrap">
          {discovered} <span className="text-gray-400 font-normal">of</span> {TOTAL_SLOTS} <span className="text-gray-400 font-normal">instances</span>
        </span>

        {/* Mini progress bar */}
        <div className="w-20 h-1.5 bg-gray-700 rounded-full overflow-hidden flex-shrink-0" title={`${pct}% discovered`}>
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{
              width: `${pct}%`,
              background: pct === 100 ? '#22c55e' : pct > 50 ? '#eab308' : '#ef4444',
            }}
          />
        </div>

        {/* Ready badge */}
        <span className={`px-1.5 py-0.5 rounded font-medium ${ready === discovered && ready > 0 ? 'bg-green-500/20 text-green-400' : 'bg-yellow-500/20 text-yellow-300'}`}>
          {ready} ready
        </span>

        {/* Expand chevron */}
        <svg className={`w-3 h-3 text-gray-500 transition-transform ${expanded ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {/* Expanded panel — per-instance details */}
      {expanded && (
        <div className="px-3 pb-3 space-y-2 border-t border-white/5 pt-2">
          {/* Instance dot grid */}
          <div className="flex items-center gap-1.5 flex-wrap">
            {Array.from({ length: TOTAL_SLOTS }).map((_, i) => {
              const inst = instances[i];
              return inst ? <InstanceDot key={inst.id} instance={inst} /> : <EmptyDot key={`empty-${i}`} />;
            })}
          </div>

          {/* Per-instance list */}
          <div className="grid grid-cols-3 gap-x-4 gap-y-1 text-[10px]">
            {instances.map(inst => {
              const cfg = stateFor(inst.status);
              const name = inst.name || inst.hostname || inst.id;
              return (
                <div key={inst.id} className="flex items-center space-x-1.5 truncate">
                  <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${cfg.color}`} />
                  <span className="text-gray-300 truncate">{name}</span>
                  <span className={`${cfg.text} flex-shrink-0`}>{cfg.label}</span>
                </div>
              );
            })}
          </div>

          {/* Footer: mode + refresh */}
          <div className="flex items-center justify-between text-[10px] text-gray-500 pt-1">
            <span>{mode === 'kubernetes-endpoints' ? 'Endpoints' : isAuto ? 'Pod' : 'Static'} discovery</span>
            <div className="flex items-center space-x-2">
              {lastUpdate && <span>Updated {new Date(lastUpdate).toLocaleTimeString()}</span>}
              <button
                onClick={(e) => { e.stopPropagation(); handleRefresh(); }}
                disabled={isRefreshing}
                className={`p-0.5 rounded transition-colors ${isRefreshing ? 'text-gray-600 cursor-not-allowed' : 'text-blue-400 hover:text-blue-300 hover:bg-white/10'}`}
                title="Refresh discovery"
              >
                <svg className={`w-3.5 h-3.5 ${isRefreshing ? 'animate-spin' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}