import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { buildRuntimeStatusWsUrl } from './wsClient';
import { useNotificationsContext } from '../contexts/NotificationsContext';

interface RuntimeStatusEvent {
  environmentId: string;
  environmentName: string;
  runtimeId: string;
  status: string;
}

function pushRuntimeNotification(addNotification: ReturnType<typeof useNotificationsContext>['addNotification'], event: RuntimeStatusEvent) {
  const offline = event.status === 'OFFLINE';
  addNotification({
    type: offline ? 'warning' : 'success',
    title: offline ? 'Runtime Offline' : 'Runtime Online',
    message: offline ? `Runtime ${event.runtimeId} in environment ${event.environmentName} (${event.environmentId}) has gone offline.` : `Runtime ${event.runtimeId} in environment ${event.environmentName} (${event.environmentId}) is now running.`,
    timestamp: new Date(),
    read: false,
    avatar: offline ? '!' : '✓',
  });
}

// Opens a plain WebSocket to /runtime-status?environmentId=&token= and
// reconnects with exponential backoff whenever the connection drops.
// On each message the relevant TanStack Query cache entries are invalidated
// and a notification is pushed to the global notification panel.
export function useRuntimeStatusSubscription(environmentId: string | undefined) {
  const queryClient = useQueryClient();
  const { addNotification } = useNotificationsContext();
  const addNotificationRef = useRef(addNotification);
  const retryRef = useRef(0);
  const wsRef = useRef<WebSocket | null>(null);

  // Keep the ref current on every render without re-opening sockets.
  addNotificationRef.current = addNotification;

  useEffect(() => {
    if (!environmentId) return;
    let cancelled = false;

    async function connect() {
      if (cancelled) return;
      const url = await buildRuntimeStatusWsUrl(environmentId!);
      if (cancelled) return;
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        console.info('[ws] connected', environmentId);
        retryRef.current = 0;
      };

      ws.onmessage = (evt) => {
        try {
          const event: RuntimeStatusEvent = JSON.parse(evt.data as string);
          console.log('[ws] event received', event);
          pushRuntimeNotification(addNotificationRef.current, event);
          queryClient.invalidateQueries({
            predicate: (query) => {
              const key = query.queryKey;
              return Array.isArray(key) && ['runtimes', 'componentRuntimes', 'projectRuntimes'].includes(key[0] as string) && key.includes(environmentId);
            },
          });
        } catch {
          console.warn('[ws] failed to parse message', evt.data);
        }
      };

      ws.onerror = (err) => console.warn('[ws] error', environmentId, err);

      ws.onclose = () => {
        if (cancelled) return;
        // Exponential backoff: 1s, 2s, 4s, …, capped at 30s
        const delay = Math.min(1000 * 2 ** retryRef.current, 30_000);
        retryRef.current += 1;
        console.info(`[ws] closed, reconnecting in ${delay}ms`, environmentId);
        setTimeout(connect, delay);
      };
    }

    connect();

    return () => {
      cancelled = true;
      wsRef.current?.close();
      wsRef.current = null;
    };
    // addNotification intentionally excluded — held in a ref to avoid tearing down sockets on every notification.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [environmentId, queryClient]);
}

// Subscribes to runtime status changes for multiple environments at once.
// Used by AppLayout so notifications are active on every page.
export function useMultiEnvRuntimeStatusSubscription(environmentIds: string[]) {
  const queryClient = useQueryClient();
  const { addNotification } = useNotificationsContext();
  const addNotificationRef = useRef(addNotification);

  // Keep the ref current on every render without re-opening sockets.
  addNotificationRef.current = addNotification;

  useEffect(() => {
    console.log('[ws] subscribing to environments:', environmentIds);
    if (environmentIds.length === 0) return;

    const sockets: WebSocket[] = [];
    const retries: number[] = environmentIds.map(() => 0);
    let cancelled = false;

    function connectFor(index: number) {
      const environmentId = environmentIds[index];

      async function connect() {
        if (cancelled) return;
        const url = await buildRuntimeStatusWsUrl(environmentId);
        if (cancelled) return;
        const ws = new WebSocket(url);
        sockets[index] = ws;

        ws.onopen = () => {
          console.info('[ws] connected', environmentId);
          retries[index] = 0;
        };

        ws.onmessage = (evt) => {
          try {
            const event: RuntimeStatusEvent = JSON.parse(evt.data as string);
            console.log('[ws] event received', environmentId, event);
            pushRuntimeNotification(addNotificationRef.current, event);
            queryClient.invalidateQueries({
              predicate: (query) => {
                const key = query.queryKey;
                return Array.isArray(key) && ['runtimes', 'componentRuntimes', 'projectRuntimes'].includes(key[0] as string) && key.includes(environmentId);
              },
            });
          } catch {
            console.warn('[ws] failed to parse message', evt.data);
          }
        };

        ws.onerror = (err) => console.warn('[ws] error', environmentId, err);

        ws.onclose = () => {
          if (cancelled) return;
          const delay = Math.min(1000 * 2 ** retries[index], 30_000);
          retries[index] += 1;
          console.info(`[ws] closed, reconnecting in ${delay}ms`, environmentId);
          setTimeout(connect, delay);
        };
      }

      connect();
    }

    for (let i = 0; i < environmentIds.length; i++) {
      connectFor(i);
    }

    return () => {
      cancelled = true;
      sockets.forEach((ws) => ws?.close());
    };
    // addNotification intentionally excluded — held in a ref to avoid tearing down sockets on every notification.
    // Re-subscribe only when the set of environment IDs changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [environmentIds.join(','), queryClient]);
}
