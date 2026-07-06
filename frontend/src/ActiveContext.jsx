import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import useWebSocket, { WsState } from './hooks/useWebSocket';

const ActiveContext = createContext({ activeIds: [], setActiveIds: () => {}, wsState: WsState.DISCONNECTED });

export function ActiveProvider({ children }) {
  const [activeIds, setActiveIdsState] = useState([]);

  const fetchActive = useCallback(() => {
    fetch('/api/active')
      .then(r => r.json())
      .then(d => setActiveIdsState(d.active || []))
      .catch(() => {});
  }, []);

  const onMessage = useCallback((msg) => {
    if (msg && Array.isArray(msg.active)) {
      setActiveIdsState(msg.active);
    }
  }, []);

  const { state: wsState, send } = useWebSocket('/active', {
    onMessage,
    onStateChange: useCallback((next) => {
      // Re-fetch on reconnect so UI is in sync immediately
      if (next === WsState.CONNECTED) fetchActive();
    }, [fetchActive]),
  });

  // Initial HTTP fetch (covers the window before WS connects)
  useEffect(() => { fetchActive(); }, [fetchActive]);

  const setActiveIds = useCallback(ids => {
    const arr = Array.isArray(ids) ? ids : [ids];
    setActiveIdsState(arr);
    // Send over WS if available, fall back to HTTP POST
    send({ ids: arr });
    fetch('/api/active', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids: arr })
    }).catch(() => {});
  }, [send]);

  return (
    <ActiveContext.Provider value={{ activeIds, setActiveIds, wsState }}>
      {children}
    </ActiveContext.Provider>
  );
}

export function useActive() {
  return useContext(ActiveContext);
}
