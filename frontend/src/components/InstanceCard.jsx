import React, { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import VNCViewerSwitcher from './VNCViewerSwitcher';
import useWebRTC from '../hooks/useWebRTC';
import useInstanceRecorder from '../hooks/useInstanceRecorder';
import AudioSinkSelector from './AudioSinkSelector';
import QualityIndicator from './QualityIndicator';

/**
 * Individual instance card component for the 3x3 grid
 * Styled to match LEGO Loco character cards with red borders, yellow accents, and cream backgrounds
 * Now includes full audio controls: volume slider, mute toggle, audio level meter,
 * and per-instance WebRTC stream recording.
 *
 * Props:
 * - instance: instance object with id, status, provisioned, etc.
 * - isActive: whether this card is currently focused
 * - onClick: callback when card is clicked
 */
/**
 * The address other players type into LEGO LOCO's TCP/IP join box to join this
 * instance's game. Click to copy — it is needed at a moment when the user is
 * looking at a Windows 98 dialog inside a VNC canvas and cannot copy from it.
 *
 * `carrier: 0` means the guest's link has no carrier, so nothing it sends
 * reaches the LAN. The address is still correct, it just will not answer yet —
 * worth showing rather than hiding, because a greyed-out address with a reason
 * is far less confusing than a plausible one that silently never connects.
 */
function JoinAddress({ guestNetwork }) {
  const [copied, setCopied] = useState(false);
  if (!guestNetwork?.ip) return null;

  const live = guestNetwork.carrier === 1;
  const copy = (e) => {
    e.stopPropagation();
    navigator.clipboard?.writeText(guestNetwork.ip).then(
      () => { setCopied(true); setTimeout(() => setCopied(false), 1200); },
      () => {},
    );
  };

  return (
    <button
      onClick={copy}
      className={`mt-1 block w-full text-left font-mono text-[11px] leading-tight ${
        live ? 'text-blue-700 hover:text-blue-900' : 'text-gray-400 hover:text-gray-600'
      }`}
      title={live
        ? `LAN address — type this into LEGO LOCO's TCP/IP box to join this instance. Click to copy.`
        : `LAN address ${guestNetwork.ip}, but ${guestNetwork.pcap_device || 'the guest link'} has no carrier, so the guest cannot reach the LAN yet.`}
    >
      {copied ? '✓ copied' : `⇄ ${guestNetwork.ip}${live ? '' : ' (no link)'}`}
    </button>
  );
}

export default function InstanceCard({ instance, isActive, onClick, onFullscreen }) {
  const { videoRef, loading, audioLevel, connectionQuality } = useWebRTC(instance.id);
  // Only trust the WebRTC <video> element once the peer connection has
  // actually reached 'connected'. `loading` alone is unreliable: it flips
  // to false the moment a single track arrives via ontrack, even if ICE
  // later fails/disconnects and no further frames ever flow. That left the
  // UI stuck on a permanently black <video> instead of falling back to the
  // (working) NoVNC viewer. Falling back whenever the connection isn't
  // actively healthy fixes this without touching the WebRTC path itself.
  //
  // In environments where WebRTC media can't traverse (e.g. ICE candidates
  // pointing at cluster-internal pod IPs that the browser can't reach), the
  // peer connection can flap connecting -> connected -> failed repeatedly.
  // Naively re-showing <video> on every transient 'connected' blip causes
  // VNCViewerSwitcher/NoVNCViewer to unmount+remount in lockstep, which kills
  // and reopens the otherwise-stable NoVNC connection over and over. Once
  // we've seen the WebRTC connection fail for this instance, stick with the
  // NoVNC fallback for the rest of this component's lifetime instead of
  // fighting back and forth.
  const webrtcFailedRef = useRef(false);
  if (connectionQuality.connectionState === 'failed' || connectionQuality.connectionState === 'disconnected') {
    webrtcFailedRef.current = true;
  }
  const webrtcHealthy = !loading && connectionQuality.connectionState === 'connected' && !webrtcFailedRef.current;
  const { recording, startRecording, stopRecording } = useInstanceRecorder(
    videoRef, 'webm', instance.id || 'instance'
  );
  const [volume, setVolumeState] = useState(1);
  const [muted, setMuted] = useState(true);
  const [restarting, setRestarting] = useState(false);

  // Restart = delete the pod; the StatefulSet brings it back with the same
  // ordinal, disk and DNS name. Discovery then walks it not-ready -> ready on
  // its own, so there is nothing to poll here beyond clearing the button.
  const handleRestart = async (e) => {
    e.stopPropagation();
    if (restarting) return;
    setRestarting(true);
    try {
      const res = await fetch(`/api/instances/${instance.id}/restart`, { method: 'POST' });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        console.error('[InstanceCard] restart failed', res.status, body);
      }
    } catch (err) {
      console.error('[InstanceCard] restart request failed', err);
    } finally {
      // Boot takes a couple of minutes; keep the button disabled long enough
      // that it is not mashed into a restart loop.
      setTimeout(() => setRestarting(false), 15000);
    }
  };
  const levelRef = useRef(null);

  // Sync volume / mute to the <video> element
  useEffect(() => {
    const vid = videoRef?.current;
    if (!vid) return;
    vid.volume = volume;
    vid.muted = muted;
  }, [volume, muted, videoRef]);

  // Animate the audio level meter bar
  useEffect(() => {
    if (!levelRef.current) return;
    const pct = Math.min(audioLevel * 100, 100);
    levelRef.current.style.width = `${pct}%`;
    levelRef.current.style.backgroundColor =
      pct > 75 ? '#ef4444' : pct > 40 ? '#eab308' : '#22c55e';
  }, [audioLevel]);

  const getStatusColor = (status) => {
    switch (status) {
      case 'ready':
        return 'lego-status-ready';
      case 'running':
        return 'lego-status-running';
      case 'booting':
        return 'lego-status-booting';
      case 'degraded':
        return 'bg-orange-500'; // Custom class for degraded
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
      case 'degraded':
        return 'Degraded';
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
      case 'degraded':
        return {
          icon: '⚠️',
          title: 'Degraded',
          subtitle: instance.health?.details || 'Service check failed',
          bgClass: 'bg-orange-100',
          textClass: 'text-orange-800',
          iconBg: 'bg-orange-200 border-orange-400'
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
      onDoubleClick={(e) => {
        e.stopPropagation();
        if (onFullscreen && instance.provisioned) onFullscreen();
      }}
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
      {/* Header with instance ID and status - styled like LEGO character card name plate */}
      <div className="relative bg-gradient-to-b from-yellow-200 to-yellow-100 border-b-4 border-red-700 shadow-inner" style={{ zIndex: 2 }}>
        <div className="p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="lego-name-plate px-3 py-2 bg-white border-3 border-gray-500 rounded-lg shadow-lg">
              <span className="text-sm font-bold text-black lego-text tracking-wide uppercase">
                {instance.name || instance.id}
              </span>
              <JoinAddress guestNetwork={instance.guestNetwork} />
            </div>
            <div className="flex items-center space-x-2">
              <div
                className={`w-5 h-5 rounded ${getStatusColor(instance.status)} border-3 border-black/30 shadow-sm`}
                title={instance.health?.details || getStatusText(instance.status, instance.provisioned)}
              />
              {/* Quality Indicator - compact display */}
              {instance.provisioned && (
                <QualityIndicator instanceId={instance.id} compact={true} />
              )}
            </div>
          </div>

          {/* Audio controls row */}
          <div className="flex flex-col gap-1.5">
            {/* Mute toggle + Volume slider + Record + Fullscreen */}
            <div className="flex items-center gap-2">
              <button
                onClick={(e) => { e.stopPropagation(); setMuted((m) => !m); }}
                className={`lego-mini-button text-xs font-bold shadow-lg ${
                  muted
                    ? 'bg-gray-400 border-gray-600 text-white'
                    : 'bg-green-500 border-green-700 text-white'
                }`}
                title={muted ? 'Unmute audio' : 'Mute audio'}
                aria-pressed={!muted}
              >
                {muted ? '🔇' : '🔊'}
              </button>
              <input
                type="range"
                min="0"
                max="1"
                step="0.01"
                value={volume}
                onChange={(e) => setVolumeState(parseFloat(e.target.value))}
                onClick={(e) => e.stopPropagation()}
                className="flex-1 h-1.5 accent-yellow-400"
                aria-label={`Volume for ${instance.name || instance.id}`}
                title={`Volume: ${Math.round(volume * 100)}%`}
              />
              <span className="text-xs font-bold text-black w-8 text-right">{Math.round(volume * 100)}%</span>
              <button
                onClick={(e) => { e.stopPropagation(); recording ? stopRecording() : startRecording(); }}
                className={`lego-mini-button text-xs font-bold shadow-lg ${
                  recording
                    ? 'bg-red-500 border-red-700 text-white animate-pulse'
                    : 'bg-blue-500 border-blue-700 text-white'
                }`}
                title={recording ? 'Stop recording' : 'Record this instance stream'}
                aria-pressed={recording}
              >
                {recording ? '⏹' : '⏺'}
              </button>
              {instance.provisioned && (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    if (onFullscreen) onFullscreen();
                  }}
                  className="lego-mini-button bg-green-600 border-green-800 hover:bg-green-500 text-white shadow-lg"
                  title="Fullscreen control (or double-click card)"
                >
                  ⛶
                </button>
              )}
              {instance.provisioned && (
                <button
                  onClick={handleRestart}
                  disabled={restarting}
                  className={`lego-mini-button text-white shadow-lg ${
                    restarting
                      ? 'bg-gray-500 border-gray-700 cursor-wait'
                      : 'bg-orange-600 border-orange-800 hover:bg-orange-500'
                  }`}
                  title={restarting ? 'Restarting…' : 'Restart this machine (rebuilds the pod)'}
                >
                  {restarting ? '…' : '⟳'}
                </button>
              )}
            </div>
            {/* Audio level meter */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-600">🎵</span>
              <div className="flex-1 h-1.5 bg-gray-300 rounded-full overflow-hidden">
                <div
                  ref={levelRef}
                  className="h-full rounded-full transition-all duration-75"
                  style={{ width: '0%', backgroundColor: '#22c55e' }}
                />
              </div>
              <AudioSinkSelector mediaRef={videoRef} />
            </div>
          </div>
        </div>
      </div>

      {/* VNC Content Area - styled like the character portrait area */}
      <div className="relative aspect-[4/3] lego-stream-area overflow-hidden bg-black">
        {instance.provisioned && (instance.ready || instance.status === 'ready' || instance.status === 'running') ? (
          <>
            {instance.id?.startsWith('demo-') ? (
              <div className="w-full h-full bg-gradient-to-br from-blue-900 via-blue-800 to-blue-900 flex items-center justify-center relative overflow-hidden">
                {/* Simulated game content */}
                <div className="absolute inset-0">
                  <div className="w-full h-full bg-gradient-to-b from-green-400 to-green-600 relative">
                    {/* LEGO railway grid pattern */}
                    <div className="absolute inset-0 opacity-30">
                      <div className="grid grid-cols-8 grid-rows-6 h-full w-full">
                        {Array(48).fill(0).map((_, i) => (
                          <div key={i} className="border border-gray-300/20"></div>
                        ))}
                      </div>
                    </div>

                    {/* Simulated LEGO elements */}
                    <div className="absolute top-1/4 left-1/4 w-8 h-8 bg-red-500 rounded-sm border-2 border-red-700"></div>
                    <div className="absolute top-1/2 right-1/3 w-6 h-6 bg-yellow-400 rounded-sm border-2 border-yellow-600"></div>
                    <div className="absolute bottom-1/3 left-1/2 w-10 h-4 bg-blue-500 rounded-sm border-2 border-blue-700"></div>

                    {/* Simulated locomotive */}
                    <div className="absolute bottom-1/4 left-1/3 flex items-center space-x-1">
                      <div className="w-3 h-2 bg-black rounded-sm"></div>
                      <div className="w-4 h-3 bg-red-600 rounded-sm border border-red-800"></div>
                      <div className="w-3 h-2 bg-blue-600 rounded-sm border border-blue-800"></div>
                    </div>
                  </div>
                </div>

                {/* Active stream indicator */}
                <div className="absolute top-2 right-2 w-3 h-3 bg-green-400 rounded-full border-2 border-white animate-pulse"></div>

                {/* Stream overlay text */}
                <div className="absolute bottom-2 left-2 text-white text-xs font-bold bg-black/50 px-2 py-1 rounded">
                  ▶ LIVE STREAM
                </div>
              </div>
            ) : (
              /* Real Instance: WebRTC Video or Fallback VNC */
              <>
                {webrtcHealthy ? (
                  <video
                    ref={videoRef}
                    className="w-full h-full object-contain bg-black"
                    autoPlay
                    playsInline
                  />
                ) : (
                  <VNCViewerSwitcher instanceId={instance.id} />
                )}
              </>
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
