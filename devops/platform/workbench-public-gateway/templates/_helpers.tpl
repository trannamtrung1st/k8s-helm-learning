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

{{- define "workbench-public-gateway.httpsListenersEnabled" -}}
{{- $enabled := false -}}
{{- range .Values.httpsListeners -}}
{{- if .enabled -}}
{{- $enabled = true -}}
{{- end -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{/*
cert-manager Gateway annotations (https://cert-manager.io/docs/usage/gateway/).
Emitted when any HTTPS listener is enabled.
*/}}
{{- define "workbench-public-gateway.certManagerAnnotations" -}}
{{- if include "workbench-public-gateway.httpsListenersEnabled" . | eq "true" }}
{{- $cm := .Values.certManager }}
{{- if .Values.global.workbenchPki.caClusterIssuer }}
cert-manager.io/cluster-issuer: {{ .Values.global.workbenchPki.caClusterIssuer }}
{{- end }}
{{- with $cm.commonName }}
cert-manager.io/common-name: {{ . | quote }}
{{- end }}
{{- with $cm.duration }}
cert-manager.io/duration: {{ . | quote }}
{{- end }}
{{- with $cm.renewBefore }}
cert-manager.io/renew-before: {{ . | quote }}
{{- end }}
{{- with $cm.usages }}
cert-manager.io/usages: {{ . | quote }}
{{- end }}
{{- with $cm.privateKeyAlgorithm }}
cert-manager.io/private-key-algorithm: {{ . | quote }}
{{- end }}
{{- with $cm.privateKeySize }}
cert-manager.io/private-key-size: {{ . | quote }}
{{- end }}
{{- with $cm.privateKeyRotationPolicy }}
cert-manager.io/private-key-rotation-policy: {{ . | quote }}
{{- end }}
{{- $org := default (include "workbench-public-gateway.partOf" . | title) $cm.subjectOrganizations }}
{{- if $org }}
cert-manager.io/subject-organizations: {{ $org | quote }}
{{- end }}
{{- with $cm.revisionHistoryLimit }}
cert-manager.io/revision-history-limit: {{ . | quote }}
{{- end }}
{{- range $key, $value := $cm.extraAnnotations }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end -}}
