const DEFAULT_API_BASE_URL = 'http://localhost:8080/api/wb'

/** API base URL: runtime config.js (Helm ConfigMap) → Vite env → default. */
export function getApiBaseUrl(): string {
  const runtime = window.__WORKBENCH_CONFIG__?.apiBaseUrl
  const buildTime = import.meta.env.VITE_API_BASE_URL
  return (runtime || buildTime || DEFAULT_API_BASE_URL).replace(/\/$/, '')
}
