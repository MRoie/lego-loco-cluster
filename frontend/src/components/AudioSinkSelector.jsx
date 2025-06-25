import React, { useEffect, useState } from 'react';

/**
 * Dropdown to pick an audio output device for a given media element.
 * Requires browser support for HTMLMediaElement.setSinkId.
 */
export default function AudioSinkSelector({ mediaRef }) {
  const [devices, setDevices] = useState([]);
  const [sinkId, setSinkId] = useState('');

  useEffect(() => {
    async function fetchDevices() {
      if (!navigator.mediaDevices?.enumerateDevices) return;
      try {
        const list = await navigator.mediaDevices.enumerateDevices();
        setDevices(list.filter(d => d.kind === 'audiooutput'));
      } catch (e) {
        console.error('Failed to enumerate audio devices', e);
      }
    }
    fetchDevices();
  }, []);

  useEffect(() => {
    if (!mediaRef?.current) return;
    if (typeof mediaRef.current.setSinkId !== 'function') return;
    if (!sinkId) return;
    mediaRef.current.setSinkId(sinkId).catch(err => {
      console.error('setSinkId failed', err);
    });
  }, [sinkId, mediaRef]);

  if (devices.length <= 1 || typeof HTMLMediaElement === 'undefined' ||
      typeof HTMLMediaElement.prototype.setSinkId !== 'function') {
    return null;
  }

  return (
    <select
      className="mt-1 text-xs bg-gray-700 text-white rounded"
      value={sinkId}
      onChange={e => setSinkId(e.target.value)}
    >
      <option value="">Default</option>
      {devices.map(d => (
        <option key={d.deviceId} value={d.deviceId}>{d.label || d.deviceId}</option>
      ))}
    </select>
  );
}
