import React, { useState, useEffect, useRef } from 'react';

/**
 * Lego-themed color constants
 */
const LEGO = {
  green: '#00A651',
  yellow: '#FFD700',
  red: '#C4281C',
  blue: '#0055BF',
  darkGray: '#4A4A4A',
};

/**
 * Thresholds for metric color coding
 */
const THRESHOLDS = {
  packetLoss: { green: 1, yellow: 5 },       // % — green < 1, yellow < 5, red >= 5
  latency: { green: 50, yellow: 150 },        // ms
  fps: { green: 24, yellow: 15 },             // frames — green >= 24, yellow >= 15, red < 15
  bandwidth: { green: 500000, yellow: 200000 }, // bytes/s
};

function badge(value, thresholds, higherIsBetter = false) {
  let color;
  if (higherIsBetter) {
    color = value >= thresholds.green ? LEGO.green
      : value >= thresholds.yellow ? LEGO.yellow
      : LEGO.red;
  } else {
    color = value <= thresholds.green ? LEGO.green
      : value <= thresholds.yellow ? LEGO.yellow
      : LEGO.red;
  }
  return color;
}

function formatBandwidth(bps) {
  if (bps >= 1_000_000) return `${(bps / 1_000_000).toFixed(1)} MB/s`;
  if (bps >= 1_000) return `${(bps / 1_000).toFixed(0)} KB/s`;
  return `${bps} B/s`;
}

function MiniTrend({ data, color, height = 32, width = 120 }) {
  if (!data || data.length < 2) return null;
  const max = Math.max(...data, 1);
  const min = Math.min(...data, 0);
  const range = max - min || 1;
  const step = width / (data.length - 1);

  const points = data.map((v, i) => {
    const x = i * step;
    const y = height - ((v - min) / range) * height;
    return `${x},${y}`;
  }).join(' ');

  return (
    <svg width={width} height={height} className="inline-block">
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function MetricCard({ label, value, unit, color, trend }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs font-bold uppercase tracking-wide" style={{ color: LEGO.darkGray }}>
        {label}
      </span>
      <div className="flex items-baseline gap-1">
        <span className="text-lg font-bold" style={{ color }}>{value}</span>
        {unit && <span className="text-xs" style={{ color: LEGO.darkGray }}>{unit}</span>}
      </div>
      {trend && <MiniTrend data={trend} color={color} />}
    </div>
  );
}

function InstanceQualityCard({ instanceId, stats }) {
  const historyRef = useRef({
    packetLoss: [],
    latency: [],
    fps: [],
    bandwidth: [],
  });

  // Append latest data point, keep last 60
  useEffect(() => {
    if (!stats) return;
    const h = historyRef.current;
    h.packetLoss = [...h.packetLoss.slice(-59), stats.packetLoss ?? 0];
    h.latency = [...h.latency.slice(-59), stats.latency ?? 0];
    h.fps = [...h.fps.slice(-59), stats.frameRate ?? 0];
    h.bandwidth = [...h.bandwidth.slice(-59), stats.bandwidth?.inbound ?? 0];
  }, [stats]);

  if (!stats) {
    return (
      <div className="bg-white/80 rounded-xl p-4 border-2 border-gray-200 shadow-sm">
        <h3 className="text-sm font-bold mb-2" style={{ color: LEGO.blue }}>{instanceId}</h3>
        <p className="text-xs text-gray-400">No data</p>
      </div>
    );
  }

  const plColor = badge(stats.packetLoss ?? 0, THRESHOLDS.packetLoss);
  const latColor = badge(stats.latency ?? 0, THRESHOLDS.latency);
  const fpsColor = badge(stats.frameRate ?? 0, THRESHOLDS.fps, true);
  const bwColor = badge(stats.bandwidth?.inbound ?? 0, THRESHOLDS.bandwidth, true);
  const h = historyRef.current;

  return (
    <div className="bg-white/90 rounded-xl p-4 border-2 shadow-sm hover:shadow-md transition-shadow"
         style={{ borderColor: plColor }}>
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-bold" style={{ color: LEGO.blue }}>{instanceId}</h3>
        <span className="text-xs px-2 py-0.5 rounded-full text-white font-bold"
              style={{ backgroundColor: plColor }}>
          {stats.connectionState ?? 'unknown'}
        </span>
      </div>

      <div className="flex items-center gap-2 mb-2 text-xs text-gray-500">
        {stats.resolution && <span>{stats.resolution}</span>}
        {stats.codec && <span>• {stats.codec.replace('video/', '')}</span>}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <MetricCard label="Packet Loss" value={(stats.packetLoss ?? 0).toFixed(1)} unit="%" color={plColor} trend={h.packetLoss} />
        <MetricCard label="Latency" value={stats.latency ?? 0} unit="ms" color={latColor} trend={h.latency} />
        <MetricCard label="FPS" value={stats.frameRate ?? 0} unit="fps" color={fpsColor} trend={h.fps} />
        <MetricCard label="Bandwidth" value={formatBandwidth(stats.bandwidth?.inbound ?? 0)} color={bwColor} trend={h.bandwidth} />
      </div>
    </div>
  );
}

/**
 * Quality Dashboard — per-instance quality metrics in a compact grid.
 * Consumes stats objects keyed by instance ID.
 *
 * @param {{ statsMap: Record<string, object> }} props
 *   statsMap — { [instanceId]: connectionQuality } from useWebRTC
 */
export default function QualityDashboard({ statsMap = {} }) {
  const entries = Object.entries(statsMap);

  if (entries.length === 0) {
    return (
      <div className="p-6 text-center text-gray-500 text-sm">
        No stream quality data available. Instances will appear here once streaming.
      </div>
    );
  }

  return (
    <div className="p-4">
      <h2 className="text-lg font-bold mb-4" style={{ color: LEGO.blue }}>
        Stream Quality Dashboard
      </h2>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {entries.map(([id, stats]) => (
          <InstanceQualityCard key={id} instanceId={id} stats={stats} />
        ))}
      </div>
    </div>
  );
}
