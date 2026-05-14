{{- define "platform.namespaces.namespace" -}}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .name }}
  labels:
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/part-of: {{ .partOf }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    workbench.io/purpose: {{ .purpose }}
{{- end -}}