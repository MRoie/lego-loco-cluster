import React from 'react';

export default function VRToast({ message }) {
  if (!message) return null;
  return (
    <a-entity position="0 2 -2">
      <a-plane width="2" height="0.5" color="#222" opacity="0.8"></a-plane>
      <a-text value={message} align="center" color="#FFF" width="1.8" position="0 0 0.01"></a-text>
    </a-entity>
  );
}
