{{- define "workbench.api.namespace" -}}
{{- .Values.global.workbenchNamespaces.apps.name -}}
{{- end -}}

{{- define "workbench.api.labels.selector" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
{{- end -}}

{{- define "workbench.api.labels.standard" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/instance: {{ .Values.instance }}
app.kubernetes.io/version: {{ .Values.image.tag }}
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "workbench.api.labels.pod" -}}
{{- include "workbench.api.labels.standard" . }}
{{- if .Values.environment }}
workbench.io/environment: {{ .Values.environment }}
{{- end }}
{{- end -}}
