{{- define "workbench.app.namespace" -}}
{{- .Values.global.workbenchNamespaces.apps.name -}}
{{- end -}}

{{- define "workbench.app.labels.selector" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
{{- end -}}

{{- define "workbench.app.labels.standard" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/instance: {{ .Values.instance }}
app.kubernetes.io/version: {{ .Values.image.tag }}
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "workbench.app.labels.pod" -}}
{{- include "workbench.app.labels.standard" . }}
{{- if .Values.environment }}
workbench.io/environment: {{ .Values.environment }}
{{- end }}
{{- end -}}
