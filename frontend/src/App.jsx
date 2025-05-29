import React, { useState } from 'react';
import { motion } from 'framer-motion';
// import { useHotkeys } from 'react-hotkeys-hook';

const instances = [
  // ...import from config/instances.json in real app
  { id: 'instance-0', streamUrl: 'http://localhost:6080/vnc0' },
  { id: 'instance-1', streamUrl: 'http://localhost:6080/vnc1' },
  { id: 'instance-2', streamUrl: 'http://localhost:6080/vnc2' },
  { id: 'instance-3', streamUrl: 'http://localhost:6080/vnc3' },
  { id: 'instance-4', streamUrl: 'http://localhost:6080/vnc4' },
  { id: 'instance-5', streamUrl: 'http://localhost:6080/vnc5' },
  { id: 'instance-6', streamUrl: 'http://localhost:6080/vnc6' },
  { id: 'instance-7', streamUrl: 'http://localhost:6080/vnc7' },
  { id: 'instance-8', streamUrl: 'http://localhost:6080/vnc8' },
];

export default function App() {
  const [active, setActive] = useState(0);
  const [zoom, setZoom] = useState(1);

  // TODO: Wire up hotkeys for focus/zoom

  return (
    <div className="min-h-screen bg-gray-900 flex items-center justify-center">
      <div className="grid grid-cols-3 gap-6 w-[90vw] h-[90vh]">
        {instances.map((inst, idx) => (
          <motion.div
            key={inst.id}
            className={`border-[12px] rounded-2xl border-yellow-500 lego-style transition-transform bg-black overflow-hidden ${active === idx ? 'ring-4 ring-blue-400' : ''}`}
            onClick={() => setActive(idx)}
            animate={{ scale: active === idx ? zoom + 0.1 : 1 }}
            transition={{ type: 'spring', stiffness: 300 }}
          >
            <iframe src={inst.streamUrl} className="w-full h-full" title={inst.id} />
          </motion.div>
        ))}
      </div>
    </div>
  );
}
