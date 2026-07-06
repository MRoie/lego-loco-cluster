/**
 * Tests for the progressive loading hook: phase ordering, error handling,
 * and cleanup. Uses jsdom + mocked fetch/discovery API.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';

vi.mock('../api/discovery', () => ({
  fetchLiveInstances: vi.fn(),
}));

import { fetchLiveInstances } from '../api/discovery';
import useProgressiveLoading from './useProgressiveLoading';

const INSTANCES = [
  { id: 'instance-0', status: 'ready', provisioned: true },
  { id: 'instance-1', status: 'booting', provisioned: false },
];

describe('useProgressiveLoading', () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    fetchLiveInstances.mockResolvedValue({ instances: INSTANCES, mode: 'kubernetes-pods' });
    global.fetch = vi.fn((url) => {
      if (url === '/api/config/hotkeys') {
        return Promise.resolve({ json: () => Promise.resolve({ next: 'ctrl+tab' }) });
      }
      if (url === '/api/status') {
        return Promise.resolve({ json: () => Promise.resolve({ healthy: true }) });
      }
      return Promise.reject(new Error(`unexpected fetch: ${url}`));
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('loads critical data first, then secondary data', async () => {
    const { result } = renderHook(() => useProgressiveLoading());

    expect(result.current.loadingStates.initialLoad).toBe(true);

    await waitFor(() => expect(result.current.isCriticalDataLoaded).toBe(true));
    expect(result.current.instances).toHaveLength(2);
    expect(result.current.provisionedInstances).toHaveLength(1);
    expect(result.current.loadingStates.initialLoad).toBe(false);

    // Secondary phase starts only after critical settles
    await waitFor(() => expect(result.current.loadingStates.hotkeys).toBe(false));
    await waitFor(() => expect(result.current.loadingStates.status).toBe(false));
    expect(result.current.hotkeys).toEqual({ next: 'ctrl+tab' });
    expect(result.current.status).toEqual({ healthy: true });
  });

  it('secondary fetches do not fire before the critical phase settles', async () => {
    let resolveCritical;
    fetchLiveInstances.mockReturnValue(new Promise((res) => { resolveCritical = res; }));

    renderHook(() => useProgressiveLoading());

    // Critical still pending — no secondary fetches yet
    expect(global.fetch).not.toHaveBeenCalled();

    await act(async () => {
      resolveCritical({ instances: INSTANCES });
    });

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/config/hotkeys'));
  });

  it('records an error but completes the phase when the discovery API fails', async () => {
    fetchLiveInstances.mockRejectedValue(new Error('api down'));

    const { result } = renderHook(() => useProgressiveLoading());

    await waitFor(() => expect(result.current.loadingStates.instances).toBe(false));
    expect(result.current.errors.instances).toBeDefined();
    expect(result.current.instances).toEqual([]);
    // The overlay can dismiss — initial load still completes
    await waitFor(() => expect(result.current.loadingStates.initialLoad).toBe(false));
  });

  it('reloads instances when a discoveryRefreshed event fires', async () => {
    const { result } = renderHook(() => useProgressiveLoading());
    await waitFor(() => expect(result.current.isCriticalDataLoaded).toBe(true));

    fetchLiveInstances.mockClear();
    act(() => {
      window.dispatchEvent(new Event('discoveryRefreshed'));
    });

    await waitFor(() => expect(fetchLiveInstances).toHaveBeenCalled());
  });

  it('polls instances and status on the interval', async () => {
    const { result } = renderHook(() => useProgressiveLoading());
    await waitFor(() => expect(result.current.loadingStates.status).toBe(false));

    fetchLiveInstances.mockClear();
    await act(async () => {
      vi.advanceTimersByTime(5000);
    });
    await waitFor(() => expect(fetchLiveInstances).toHaveBeenCalled());
  });

  it('stops polling after unmount', async () => {
    const { result, unmount } = renderHook(() => useProgressiveLoading());
    await waitFor(() => expect(result.current.isCriticalDataLoaded).toBe(true));

    unmount();
    fetchLiveInstances.mockClear();
    await act(async () => {
      vi.advanceTimersByTime(15000);
    });
    expect(fetchLiveInstances).not.toHaveBeenCalled();
  });
});
