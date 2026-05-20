{{/*
Shared Workbench Helm library. Add as a chart dependency; templates are available
to the parent chart at render time (not installed as a release).
*/}}

{{- define "workbench.lib.image" -}}
{{- if .Values.global.imageRegistry -}}
{{- printf "%s/%s:%s" .Values.global.imageRegistry .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "workbench.lib.namespace.apps" -}}
{{- .Values.global.workbenchNamespaces.apps.name -}}
{{- end -}}

{{- define "workbench.lib.namespace.db" -}}
{{- .Values.global.workbenchNamespaces.db.name -}}
{{- end -}}

{{- define "workbench.lib.namespace.infra" -}}
{{- .Values.global.workbenchNamespaces.infra.name -}}
{{- end -}}

{{- define "workbench.lib.labels.selector" -}}
app.kubernetes.io/name: {{ .Values.name }}
{{- with .Values.component }}
app.kubernetes.io/component: {{ . }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.labels.selector.nameOnly" -}}
app.kubernetes.io/name: {{ .Values.name }}
{{- end -}}

{{- define "workbench.lib.labels.standard.apps" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/instance: {{ .Values.instance }}
app.kubernetes.io/version: {{ .Values.image.tag }}
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "workbench.lib.labels.standard.cronjob" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag }}
{{- end -}}

{{- define "workbench.lib.labels.standard.infra" -}}
{{- $ctx := .ctx -}}
{{- $component := .component -}}
app.kubernetes.io/name: {{ $ctx.Values.name }}
app.kubernetes.io/component: {{ $component }}
app.kubernetes.io/part-of: {{ $ctx.Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
app.kubernetes.io/version: {{ $ctx.Chart.AppVersion }}
{{- end -}}

{{- define "workbench.lib.labels.pod" -}}
{{- include "workbench.lib.labels.standard.apps" . }}
{{- if .Values.environment }}
workbench.io/environment: {{ .Values.environment }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.infraNode.affinity" -}}
nodeAffinity:
  required:
    nodeSelectorTerms:
      - matchExpressions:
          - key: {{ .Values.global.workbenchInfraNode.labelKey }}
            operator: In
            values:
              - {{ .Values.global.workbenchInfraNode.labelValue | quote }}
{{- end -}}

{{- define "workbench.lib.storageClasses.pvcName" -}}
{{- required "set global.workbenchStorageClasses.pvc.name (cluster -f overlay; local=standard, aks=managed-csi)." .Values.global.workbenchStorageClasses.pvc.name -}}
{{- end -}}
