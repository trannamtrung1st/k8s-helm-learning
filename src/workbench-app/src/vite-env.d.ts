/// <reference types="vite/client" />

interface WorkbenchRuntimeConfig {
  apiBaseUrl?: string
}

interface Window {
  __WORKBENCH_CONFIG__?: WorkbenchRuntimeConfig
}

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
