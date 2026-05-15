{{- define "workbench.redis.namespace" -}}
{{- .Values.global.workbenchNamespaces.infra.name -}}
{{- end -}}

{{- define "workbench.redis.labels.selector" -}}
app.kubernetes.io/name: {{ .Values.name }}
{{- end -}}

{{- define "workbench.redis.labels.standard" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: cache
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}
