{{- define "workbench-public-gateway.partOf" -}}
{{- required "set global.workbenchPartOf (pass -f devops/platform/platform-values/global-values.yaml)." .Values.global.workbenchPartOf -}}
{{- end -}}

{{- define "workbench-public-gateway.allowedRoutes" -}}
namespaces:
  from: Selector
  selector:
    matchLabels:
      app.kubernetes.io/part-of: {{ include "workbench-public-gateway.partOf" . }}
{{- end -}}

{{- define "workbench-public-gateway.labels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/part-of: {{ include "workbench-public-gateway.partOf" . }}
{{- end -}}
