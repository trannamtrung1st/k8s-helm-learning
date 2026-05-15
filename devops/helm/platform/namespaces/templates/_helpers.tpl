# [IMPORTANT]: comment must end with */}}

{{- /**
Context required:
- .name: the name of the namespace
- .partOf: the part of the namespace
- .purpose: the purpose of the namespace
- .Release: the release object
- .Chart: the chart object
*/}}
{{- define "platform.namespaces.namespace" -}}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .name }}
  labels:
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/part-of: {{ .partOf }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/version: {{ .Chart.AppVersion }}
    workbench.io/purpose: {{ .purpose }}
{{- end -}}