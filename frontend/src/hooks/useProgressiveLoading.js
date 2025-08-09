import { useState, useEffect, useCallback } from 'react';

/**
 * Custom hook for managing progressive data loading with loading states
 * Implements progressive loading strategy: critical data first, then secondary data
 */
export default function useProgressiveLoading() {
  const [loadingStates, setLoadingStates] = useState({
    instances: true,
    provisionedInstances: true,
    hotkeys: true,
    status: true,
    initialLoad: true
  });

  const [data, setData] = useState({
    instances: [],
    provisionedInstances: [],
    hotkeys: {},
    status: {}
  });

  const [errors, setErrors] = useState({});

  // Update loading state for specific data type
  const setLoading = useCallback((key, isLoading) => {
    setLoadingStates(prev => ({ ...prev, [key]: isLoading }));
  }, []);

  // Update data and loading state
  const setDataAndLoading = useCallback((key, newData) => {
    setData(prev => ({ ...prev, [key]: newData }));
    setLoading(key, false);
  }, [setLoading]);

  // Set error state
  const setError = useCallback((key, error) => {
    setErrors(prev => ({ ...prev, [key]: error }));
    setLoading(key, false);
  }, [setLoading]);

  // Progressive loading function - loads data in priority order
  const loadData = useCallback(async () => {
    try {
      // Phase 1: Critical data (instances and provisioned instances) - load in parallel
      setLoading('initialLoad', true);
      
      const criticalPromises = [
        fetch("/api/instances")
          .then(r => r.json())
          .then(data => setDataAndLoading('instances', data))
          .catch(e => {
            console.error("Failed to fetch instances", e);
            setError('instances', e);
          }),
        
        fetch("/api/instances/provisioned")
          .then(r => r.json())
          .then(data => setDataAndLoading('provisionedInstances', data))
          .catch(e => {
            console.error("Failed to fetch provisioned instances", e);
            setError('provisionedInstances', e);
          })
      ];

      // Wait for critical data
      await Promise.allSettled(criticalPromises);

      // Phase 2: Secondary data (hotkeys and status) - load after critical data
      const secondaryPromises = [
        fetch("/api/config/hotkeys")
          .then(r => r.json())
          .then(data => setDataAndLoading('hotkeys', data))
          .catch(e => {
            console.error("Failed to fetch hotkeys", e);
            setError('hotkeys', e);
          }),
        
        fetch("/api/status")
          .then(r => r.json())
          .then(data => setDataAndLoading('status', data))
          .catch(e => {
            console.error("Failed to fetch status", e);
            setError('status', e);
          })
      ];

      // Wait for secondary data
      await Promise.allSettled(secondaryPromises);

    } finally {
      setLoading('initialLoad', false);
    }
  }, [setDataAndLoading, setError, setLoading]);

  // Refresh specific data type
  const refreshData = useCallback(async (dataType) => {
    const endpoints = {
      instances: "/api/instances",
      provisionedInstances: "/api/instances/provisioned", 
      hotkeys: "/api/config/hotkeys",
      status: "/api/status"
    };

    if (!endpoints[dataType]) return;

    setLoading(dataType, true);
    try {
      const response = await fetch(endpoints[dataType]);
      const result = await response.json();
      setDataAndLoading(dataType, result);
    } catch (error) {
      console.error(`Failed to refresh ${dataType}`, error);
      setError(dataType, error);
    }
  }, [setDataAndLoading, setError, setLoading]);

  // Check if critical data is loaded (instances and provisioned instances)
  const isCriticalDataLoaded = !loadingStates.instances && !loadingStates.provisionedInstances;
  
  // Check if all data is loaded
  const isAllDataLoaded = Object.values(loadingStates).every(loading => !loading);

  // Check if any critical data has errors
  const hasCriticalErrors = !!(errors.instances || errors.provisionedInstances);

  return {
    // Data
    ...data,
    
    // Loading states
    loadingStates,
    isInitialLoading: loadingStates.initialLoad,
    isCriticalDataLoaded,
    isAllDataLoaded,
    
    // Error states
    errors,
    hasCriticalErrors,
    
    // Actions
    loadData,
    refreshData,
    setLoading
  };
}