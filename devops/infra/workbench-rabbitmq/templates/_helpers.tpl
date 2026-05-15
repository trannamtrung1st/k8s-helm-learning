{{- define "workbench.rabbitmq.namespace" -}}
{{- .Values.global.workbenchNamespaces.infra.name -}}
{{- end -}}

{{- define "workbench.rabbitmq.labels.selector" -}}
app.kubernetes.io/name: {{ .Values.name }}
{{- end -}}

{{- define "workbench.rabbitmq.labels.standard" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/component: broker
app.kubernetes.io/part-of: {{ .Values.global.workbenchPartOf }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}

{{- define "workbench.infraNode.affinity" -}}
nodeAffinity:
  required:
    nodeSelectorTerms:
      - matchExpressions:
          - key: {{ .Values.global.workbenchInfraNode.labelKey }}
            operator: In
            values:
              - {{ .Values.global.workbenchInfraNode.labelValue | quote }}
{{- end -}}
