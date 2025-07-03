// Entry for React app (Vite + Tailwind + Framer Motion + hotkeys)
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { ActiveProvider } from './ActiveContext';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <ActiveProvider>
      <App />
    </ActiveProvider>
  </React.StrictMode>
);
