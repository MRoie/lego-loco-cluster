import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';

const ActiveContext = createContext({ activeId: null, setActiveId: () => {} });

export function ActiveProvider({ children }) {
  const [activeId, setActiveIdState] = useState(null);

  const fetchActive = useCallback(() => {
    fetch('/api/active')
      .then(r => r.json())
      .then(d => setActiveIdState(d.active))
      .catch(() => {});
  }, []);

  const setActiveId = useCallback(id => {
    setActiveIdState(id);
    fetch('/api/active', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id })
    }).catch(() => {});
  }, []);

  useEffect(() => {
    fetchActive();
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(`${proto}://${location.host}/active`);
    ws.onmessage = e => {
      try {
        const msg = JSON.parse(e.data);
        setActiveIdState(msg.active);
      } catch {}
    };
    return () => ws.close();
  }, [fetchActive]);

  return (
    <ActiveContext.Provider value={{ activeId, setActiveId }}>
      {children}
    </ActiveContext.Provider>
  );
}

export function useActive() {
  return useContext(ActiveContext);
}
