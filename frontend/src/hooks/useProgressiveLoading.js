import { useState, useEffect, useCallback, useRef } from 'react';
import { fetchLiveInstances } from '../api/discovery';
import { createLogger } from '../utils/logger';

const logger = createLogger('useProgressiveLoading');

const POLL_INTERVAL_MS = 5000;

/**
 * Progressive data loading for the dashboard (concept from PR #74).
 *
 * Phase 1 (critical): live instances via the discovery API — the 3×3 grid
 * renders as soon as this resolves.
 * Phase 2 (secondary): hotkey config and cluster status — fetched after the
 * critical phase settles so they never block first paint.
 *
 * Also owns the 5s polling loop and the `discoveryRefreshed` listener that
 * App.jsx previously wired inline.
 */
export default function useProgressiveLoading() {
  const [instances, setInstances] = useState([]);
  const [provisionedInstances, setProvisionedInstances] = useState([]);
  const [discoveryStatus, setDiscoveryStatus] = useState(null);
  const [hotkeys, setHotkeys] = useState({});
  const [status, setStatus] = useState({});

  const [loadingStates, setLoadingStates] = useState({
    instances: true,
    provisionedInstances: true,
    hotkeys: true,
    status: true,
    initialLoad: true,
  });
  const [errors, setErrors] = useState({});
  const mountedRef = useRef(true);

  const setLoading = useCallback((key, isLoading) => {
    setLoadingStates((prev) => ({ ...prev, [key]: isLoading }));
  }, []);

  const setError = useCallback((key, error) => {
    setErrors((prev) => ({ ...prev, [key]: error }));
  }, []);

  const clearError = useCallback((key) => {
    setErrors((prev) => {
      if (!(key in prev)) return prev;
      const next = { ...prev };
      delete next[key];
      return next;
    });
  }, []);

  // Phase 1 — critical: instances (provisioned list is derived client-side)
  const loadInstances = useCallback(async () => {
    try {
      const data = await fetchLiveInstances();
      if (!mountedRef.current) return;
      const list = data.instances || [];
      setInstances(list);
      setDiscoveryStatus(data);
      setProvisionedInstances(list.filter((i) => i.provisioned || i.status === 'ready'));
      clearError('instances');
      clearError('provisionedInstances');
    } catch (e) {
      if (!mountedRef.current) return;
      logger.error('Failed to fetch live instances', { error: e.message });
      setError('instances', e);
      setError('provisionedInstances', e);
    } finally {
      if (mountedRef.current) {
        setLoading('instances', false);
        setLoading('provisionedInstances', false);
      }
    }
  }, [clearError, setError, setLoading]);

  // Phase 2 — secondary: hotkeys (once) and status
  const loadHotkeys = useCallback(async () => {
    try {
      const r = await fetch('/api/config/hotkeys');
      const data = await r.json();
      if (mountedRef.current) {
        setHotkeys(data);
        clearError('hotkeys');
      }
    } catch (e) {
      if (!mountedRef.current) return;
      logger.warn('Failed to fetch hotkeys', { error: e.message });
      setError('hotkeys', e);
    } finally {
      if (mountedRef.current) setLoading('hotkeys', false);
    }
  }, [clearError, setError, setLoading]);

  const loadStatus = useCallback(async () => {
    try {
      const r = await fetch('/api/status');
      const data = await r.json();
      if (mountedRef.current) {
        setStatus(data);
        clearError('status');
      }
    } catch (e) {
      if (!mountedRef.current) return;
      logger.warn('Failed to fetch status', { error: e.message });
      setError('status', e);
    } finally {
      if (mountedRef.current) setLoading('status', false);
    }
  }, [clearError, setError, setLoading]);

  useEffect(() => {
    mountedRef.current = true;

    // Critical first; secondary starts only after critical settles so it
    // cannot compete for the connection during first paint.
    loadInstances().then(() => {
      if (!mountedRef.current) return;
      setLoading('initialLoad', false);
      loadHotkeys();
      loadStatus();
    });

    const interval = setInterval(() => {
      loadInstances();
      loadStatus();
    }, POLL_INTERVAL_MS);

    const handleDiscoveryRefresh = () => {
      logger.info('Discovery refreshed, reloading instances');
      loadInstances();
    };
    window.addEventListener('discoveryRefreshed', handleDiscoveryRefresh);

    return () => {
      mountedRef.current = false;
      clearInterval(interval);
      window.removeEventListener('discoveryRefreshed', handleDiscoveryRefresh);
    };
  }, [loadInstances, loadHotkeys, loadStatus, setLoading]);

  const isCriticalDataLoaded = !loadingStates.instances;

  return {
    instances,
    provisionedInstances,
    discoveryStatus,
    hotkeys,
    status,
    loadingStates,
    errors,
    isCriticalDataLoaded,
    reloadInstances: loadInstances,
  };
}
