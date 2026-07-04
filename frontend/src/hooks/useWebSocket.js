/**
 * useWebSocket Hook — Resilient WebSocket with auto-reconnect
 *
 * Features:
 * - Exponential backoff reconnect (1s → 2s → 4s → 8s … max 30s)
 * - Jitter to prevent thundering herd
 * - Connection state tracking (connecting, connected, disconnected, reconnecting, failed)
 * - Max reconnect attempts (default 50) before giving up
 * - Heartbeat ping every 30s to detect stale connections
 * - Message queue during disconnection, replayed on reconnect
 * - Custom events on state change (window 'ws:statechange')
 * - Clean up on component unmount
 */

import { useEffect, useRef, useState, useCallback } from 'react';
import { createLogger } from '../utils/logger';

const logger = createLogger('useWebSocket');

/** Connection states */
export const WsState = {
  CONNECTING: 'connecting',
  CONNECTED: 'connected',
  DISCONNECTED: 'disconnected',
  RECONNECTING: 'reconnecting',
  FAILED: 'failed',
};

const DEFAULTS = {
  maxReconnectAttempts: 50,
  baseDelay: 1000,        // 1s
  maxDelay: 30000,        // 30s
  heartbeatInterval: 30000, // 30s
  heartbeatTimeout: 10000,  // 10s — pong must arrive within this
  replayQueuedMessages: true,
};

/**
 * Build a full WebSocket URL from a path like "/active".
 * Respects current page protocol (ws/wss).
 */
function buildWsUrl(path) {
  const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
  return `${proto}://${window.location.host}${path}`;
}

/**
 * Compute backoff delay with jitter.
 * delay = min(base * 2^attempt + jitter, maxDelay)
 */
function backoffDelay(attempt, base, max) {
  const exponential = base * Math.pow(2, attempt);
  const jitter = Math.random() * 0.3 * exponential; // 0-30 % jitter
  return Math.min(exponential + jitter, max);
}

/**
 * Resilient WebSocket hook.
 *
 * @param {string}   path       WebSocket endpoint path (e.g. "/active")
 * @param {object}   [opts]
 * @param {function} [opts.onMessage]   Called with parsed JSON (or raw data) for every message
 * @param {function} [opts.onStateChange] Called with (newState, prevState)
 * @param {number}   [opts.maxReconnectAttempts=50]
 * @param {number}   [opts.baseDelay=1000]
 * @param {number}   [opts.maxDelay=30000]
 * @param {number}   [opts.heartbeatInterval=30000]
 * @param {boolean}  [opts.replayQueuedMessages=true]
 * @param {boolean}  [opts.enabled=true]  Set false to disable connecting
 * @returns {{ state, send, reconnect, wsRef }}
 */
export default function useWebSocket(path, opts = {}) {
  const {
    onMessage,
    onStateChange,
    maxReconnectAttempts = DEFAULTS.maxReconnectAttempts,
    baseDelay = DEFAULTS.baseDelay,
    maxDelay = DEFAULTS.maxDelay,
    heartbeatInterval = DEFAULTS.heartbeatInterval,
    heartbeatTimeout = DEFAULTS.heartbeatTimeout,
    replayQueuedMessages = DEFAULTS.replayQueuedMessages,
    enabled = true,
  } = opts;

  const [state, setState] = useState(WsState.DISCONNECTED);

  // Refs survive across renders and effect re-runs
  const wsRef = useRef(null);
  const attemptRef = useRef(0);
  const reconnectTimerRef = useRef(null);
  const heartbeatTimerRef = useRef(null);
  const pongTimerRef = useRef(null);
  const messageQueueRef = useRef([]);
  const unmountedRef = useRef(false);

  // Keep latest callbacks in refs so we don't need them in the dep arrays
  const onMessageRef = useRef(onMessage);
  onMessageRef.current = onMessage;
  const onStateChangeRef = useRef(onStateChange);
  onStateChangeRef.current = onStateChange;

  /** Emit state change both to React state and to callback / window event */
  const setWsState = useCallback((next) => {
    setState((prev) => {
      if (prev === next) return prev;
      logger.debug('WS state change', { path, from: prev, to: next });
      if (onStateChangeRef.current) onStateChangeRef.current(next, prev);
      window.dispatchEvent(
        new CustomEvent('ws:statechange', { detail: { path, state: next, prev } }),
      );
      return next;
    });
  }, [path]);

  /** --- Heartbeat ---------------------------------------------------- */
  const startHeartbeat = useCallback((ws) => {
    stopHeartbeat();
    heartbeatTimerRef.current = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        // Send application-level ping (server echoes a pong message)
        ws.send(JSON.stringify({ type: '__ping', ts: Date.now() }));
        // Start a pong timeout
        pongTimerRef.current = setTimeout(() => {
          logger.warn('Heartbeat pong timeout, closing stale connection', { path });
          ws.close(4000, 'Heartbeat timeout');
        }, heartbeatTimeout);
      }
    }, heartbeatInterval);
  }, [path, heartbeatInterval, heartbeatTimeout]);

  const stopHeartbeat = useCallback(() => {
    if (heartbeatTimerRef.current) {
      clearInterval(heartbeatTimerRef.current);
      heartbeatTimerRef.current = null;
    }
    if (pongTimerRef.current) {
      clearTimeout(pongTimerRef.current);
      pongTimerRef.current = null;
    }
  }, []);

  /** --- Queue management --------------------------------------------- */
  const drainQueue = useCallback((ws) => {
    if (!replayQueuedMessages) {
      messageQueueRef.current = [];
      return;
    }
    while (messageQueueRef.current.length > 0 && ws.readyState === WebSocket.OPEN) {
      const msg = messageQueueRef.current.shift();
      ws.send(msg);
    }
  }, [replayQueuedMessages]);

  /** --- Send (queues when disconnected) ------------------------------ */
  const send = useCallback((data) => {
    const payload = typeof data === 'string' ? data : JSON.stringify(data);
    const ws = wsRef.current;
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(payload);
    } else {
      messageQueueRef.current.push(payload);
    }
  }, []);

  /** --- Core connect / reconnect logic ------------------------------- */
  useEffect(() => {
    if (!enabled) return;
    unmountedRef.current = false;

    function connect() {
      if (unmountedRef.current) return;
      setWsState(attemptRef.current === 0 ? WsState.CONNECTING : WsState.RECONNECTING);

      const url = buildWsUrl(path);
      let ws;
      try {
        ws = new WebSocket(url);
      } catch (err) {
        logger.error('WebSocket constructor failed', { path, error: err.message });
        scheduleReconnect();
        return;
      }
      wsRef.current = ws;

      ws.onopen = () => {
        if (unmountedRef.current) { ws.close(); return; }
        logger.info('WebSocket connected', { path, attempt: attemptRef.current });
        attemptRef.current = 0; // reset backoff on success
        setWsState(WsState.CONNECTED);
        drainQueue(ws);
        startHeartbeat(ws);
      };

      ws.onmessage = (ev) => {
        // Handle heartbeat pong
        try {
          const parsed = JSON.parse(ev.data);
          if (parsed.type === '__pong') {
            // Clear pong timeout — connection is alive
            if (pongTimerRef.current) {
              clearTimeout(pongTimerRef.current);
              pongTimerRef.current = null;
            }
            return; // don't forward to consumer
          }
          if (onMessageRef.current) onMessageRef.current(parsed);
        } catch {
          // Not JSON — forward raw
          if (onMessageRef.current) onMessageRef.current(ev.data);
        }
      };

      ws.onerror = () => {
        // onerror is always followed by onclose, so no action needed here
        // beyond logging
        logger.warn('WebSocket error', { path });
      };

      ws.onclose = (ev) => {
        stopHeartbeat();
        wsRef.current = null;
        if (unmountedRef.current) {
          setWsState(WsState.DISCONNECTED);
          return;
        }
        logger.info('WebSocket closed', { path, code: ev.code, reason: ev.reason });
        scheduleReconnect();
      };
    }

    function scheduleReconnect() {
      if (unmountedRef.current || reconnectTimerRef.current) return;

      if (attemptRef.current >= maxReconnectAttempts) {
        logger.error('Max reconnect attempts reached, giving up', {
          path,
          attempts: attemptRef.current,
        });
        setWsState(WsState.FAILED);
        return;
      }

      const delay = backoffDelay(attemptRef.current, baseDelay, maxDelay);
      logger.info('Scheduling reconnect', {
        path,
        attempt: attemptRef.current + 1,
        delayMs: Math.round(delay),
      });
      setWsState(WsState.RECONNECTING);
      attemptRef.current += 1;

      reconnectTimerRef.current = setTimeout(() => {
        reconnectTimerRef.current = null;
        connect();
      }, delay);
    }

    connect();

    return () => {
      unmountedRef.current = true;
      // Cleanup timers
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current);
        reconnectTimerRef.current = null;
      }
      stopHeartbeat();
      // Close socket
      if (wsRef.current) {
        wsRef.current.close(1000, 'Component unmount');
        wsRef.current = null;
      }
      setWsState(WsState.DISCONNECTED);
    };
  }, [path, enabled, maxReconnectAttempts, baseDelay, maxDelay, setWsState, drainQueue, startHeartbeat, stopHeartbeat]);

  /** Manual reconnect (resets attempt counter) */
  const reconnect = useCallback(() => {
    attemptRef.current = 0;
    if (wsRef.current) {
      wsRef.current.close(1000, 'Manual reconnect');
    }
    // onclose handler will trigger scheduleReconnect with reset counter
  }, []);

  return { state, send, reconnect, wsRef };
}
