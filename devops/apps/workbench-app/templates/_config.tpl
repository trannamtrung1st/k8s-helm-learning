{{- define "workbench.app.config.js" -}}
window.__WORKBENCH_CONFIG__ = {
  apiBaseUrl: {{ .Values.config.apiBaseUrl | quote }}
};
{{- end -}}
