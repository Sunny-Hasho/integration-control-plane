import { getAccessToken, isAccessTokenExpired, refreshAccessToken } from '../auth/tokenManager';

// Build the WebSocket URL for a given environmentId.
// Auth: the JWT is embedded as ?token= since browsers cannot set custom headers
// on WebSocket upgrade requests.
export async function buildRuntimeStatusWsUrl(environmentId: string): Promise<string> {
  if (isAccessTokenExpired()) {
    await refreshAccessToken();
  }
  const token = getAccessToken();
  const base = window.API_CONFIG.wsUrl;
  const url = `${base}?environmentId=${encodeURIComponent(environmentId)}${token ? `&token=${encodeURIComponent(token)}` : ''}`;
  console.log('[wsClient] connecting to', base);
  return url;
}
