{{- define "workbench.jobs.namespace" -}}
{{- .Values.global.workbenchNamespaces.apps.name -}}
{{- end -}}

{{- define "workbench.jobs.labels.standard" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag }}
{{- end -}}
