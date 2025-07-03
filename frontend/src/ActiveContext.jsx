import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';

const ActiveContext = createContext({ activeIds: [], setActiveIds: () => {} });

export function ActiveProvider({ children }) {
  const [activeIds, setActiveIdsState] = useState([]);

  const fetchActive = useCallback(() => {
    fetch('/api/active')
      .then(r => r.json())
      .then(d => setActiveIdsState(d.active || []))
      .catch(() => {});
  }, []);

  const setActiveIds = useCallback(ids => {
    const arr = Array.isArray(ids) ? ids : [ids];
    setActiveIdsState(arr);
    fetch('/api/active', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids: arr })
    }).catch(() => {});
  }, []);

  useEffect(() => {
    fetchActive();
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(`${proto}://${location.host}/active`);
    ws.onmessage = e => {
      try {
        const msg = JSON.parse(e.data);
        if (Array.isArray(msg.active)) setActiveIdsState(msg.active);
      } catch {}
    };
    return () => ws.close();
  }, [fetchActive]);

  return (
    <ActiveContext.Provider value={{ activeIds, setActiveIds }}>
      {children}
    </ActiveContext.Provider>
  );
}

export function useActive() {
  return useContext(ActiveContext);
}
