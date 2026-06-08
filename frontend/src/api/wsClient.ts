import { getAccessToken, isAccessTokenExpired, refreshAccessToken } from '../auth/tokenManager';

// Build the WebSocket URL for a given environmentId.
// Auth: the JWT is embedded as ?token= since browsers cannot set custom headers
// on WebSocket upgrade requests.
export async function buildRuntimeStatusWsUrl(environmentId: string): Promise<string> {
  if (isAccessTokenExpired()) {
    try {
      await refreshAccessToken();
    } catch (err) {
      console.error('[wsClient] token refresh failed, cannot open WebSocket', err);
      throw new Error(`WebSocket connection aborted: token refresh failed — ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  const base = window.API_CONFIG?.wsUrl;
  if (!base) {
    console.error('[wsClient] window.API_CONFIG.wsUrl is missing or empty');
    throw new Error('WebSocket connection aborted: API_CONFIG.wsUrl is not configured');
  }

  const token = getAccessToken();
  if (!token) {
    console.error('[wsClient] no access token available after refresh, cannot open WebSocket');
    throw new Error('WebSocket connection aborted: no access token available');
  }
  const url = `${base}?environmentId=${encodeURIComponent(environmentId)}&token=${encodeURIComponent(token)}`;
  console.log('[wsClient] connecting to', base);
  return url;
}
