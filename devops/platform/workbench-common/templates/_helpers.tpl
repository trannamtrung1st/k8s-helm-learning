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

{{- define "workbench.lib.redis.clusterEnabled" -}}
{{- if .Values.global.workbenchRedis.cluster }}{{ .Values.global.workbenchRedis.cluster.enabled }}{{ else }}false{{ end -}}
{{- end -}}

{{- define "workbench.lib.redis.name" -}}
{{- .Values.global.workbenchRedis.name | default "workbench-redis" -}}
{{- end -}}

{{- define "workbench.lib.redis.replicas" -}}
{{- if .Values.global.workbenchRedis.cluster }}{{ .Values.global.workbenchRedis.cluster.replicas | default 6 }}{{ else }}1{{ end -}}
{{- end -}}

{{- define "workbench.lib.redis.endpoint" -}}
{{- $name := include "workbench.lib.redis.name" . -}}
{{- $ns := include "workbench.lib.namespace.infra" . -}}
{{- $port := .Values.global.workbenchRedis.port | default 6379 -}}
{{- printf "%s-%d.%s.%s.svc.cluster.local:%v" $name .ordinal $name $ns $port -}}
{{- end -}}

{{- define "workbench.lib.resources.container" -}}
limits:
  cpu: {{ .limitsCpu }}
  memory: {{ .limitsMemory }}
requests:
  cpu: {{ .requestsCpu }}
  memory: {{ .requestsMemory }}
{{- end -}}

{{- define "workbench.lib.probe.timing" -}}
{{- with .initialDelaySeconds }}
initialDelaySeconds: {{ . }}
{{- end }}
{{- with .periodSeconds }}
periodSeconds: {{ . }}
{{- end }}
{{- with .timeoutSeconds }}
timeoutSeconds: {{ . }}
{{- end }}
{{- with .failureThreshold }}
failureThreshold: {{ . }}
{{- end }}
{{- with .successThreshold }}
successThreshold: {{ . }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.httpRoute.corsFilter" -}}
{{- if not .allowOrigins }}{{- fail "httpRoute.cors: set allowOrigins" }}{{- end -}}
- type: CORS
  cors:
{{ omit . "enabled" | toYaml | nindent 4 }}
{{- end -}}

{{- define "workbench.lib.httpRoute.headerModifierFilters" -}}
{{- if .request.set }}
- type: RequestHeaderModifier
  requestHeaderModifier:
    set:
{{ toYaml .request.set | indent 4 }}
{{- end }}
{{- if .response.set }}
- type: ResponseHeaderModifier
  responseHeaderModifier:
    set:
{{ toYaml .response.set | indent 4 }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.httpRoute.filters" -}}
{{- with .Values.httpRoute.cors }}
{{- include "workbench.lib.httpRoute.corsFilter" . }}
{{- end }}
{{- with .Values.httpRoute.headers }}
{{- include "workbench.lib.httpRoute.headerModifierFilters" . }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.httpRoute.timeouts" -}}
{{- with .Values.httpRoute.timeouts }}
      timeouts:
        {{- with .request }}
        request: {{ . | quote }}
        {{- end }}
        {{- with .backendRequest }}
        backendRequest: {{ . | quote }}
        {{- end }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.httpRoute.backendRefs" -}}
{{- if .Values.httpRoute.backendRefs }}
{{- range .Values.httpRoute.backendRefs }}
        - name: {{ required "httpRoute.backendRefs: set name" .name }}
          port: {{ .port | default $.Values.service.port }}
          {{- with .weight }}
          weight: {{ . }}
          {{- end }}
{{- end }}
{{- else }}
        - name: {{ .Values.name }}
          port: {{ .Values.service.port }}
{{- end }}
{{- end -}}

{{- define "workbench.lib.httpRoute" -}}
{{- if .Values.httpRoute.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Values.httpRoute.name | default (printf "%s-http-route" .Values.name) }}
  namespace: {{ include "workbench.lib.namespace.apps" . }}
  labels:
    {{- include "workbench.lib.labels.standard.apps" . | nindent 4 }}
    {{- if .Values.environment }}
    workbench.io/environment: {{ .Values.environment }}
    {{- end }}
spec:
  parentRefs:
  {{- $sections := .Values.httpRoute.parentSectionNames | default (list "http" "https") }}
  {{- range $sections }}
    - name: {{ $.Values.httpRoute.parentGatewayName }}
      namespace: {{ $.Values.httpRoute.parentGatewayNamespace }}
      sectionName: {{ . }}
  {{- end }}
  {{- with .Values.httpRoute.hostname }}
  hostnames:
    - {{ . | quote }}
  {{- end }}
  rules:
  {{- range .Values.httpRoute.pathRewrites | default list }}
    - matches:
        - path:
            type: {{ .matchPathType | default "PathPrefix" }}
            value: {{ required "httpRoute.pathRewrites: set matchPath" .matchPath }}
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              {{- if eq (.rewritePathType | default "ReplacePrefixMatch") "ReplaceFullPath" }}
              type: ReplaceFullPath
              replaceFullPath: {{ required "httpRoute.pathRewrites: set rewritePath" .rewritePath }}
              {{- else }}
              type: ReplacePrefixMatch
              replacePrefixMatch: {{ required "httpRoute.pathRewrites: set rewritePath" .rewritePath }}
              {{- end }}
{{- include "workbench.lib.httpRoute.timeouts" $ }}
      backendRefs:
{{- include "workbench.lib.httpRoute.backendRefs" $ | nindent 0 }}
  {{- end }}
  {{- range .Values.httpRoute.pathRedirects | default list }}
    - matches:
        - path:
            type: {{ .matchPathType | default "Exact" }}
            value: {{ required "httpRoute.pathRedirects: set matchPath" .matchPath }}
      filters:
        - type: RequestRedirect
          requestRedirect:
            path:
              type: ReplaceFullPath
              replaceFullPath: {{ required "httpRoute.pathRedirects: set redirectPath" .redirectPath }}
            statusCode: {{ .statusCode | default 301 }}
  {{- end }}
    - matches:
        - path:
            type: {{ .Values.httpRoute.pathMatchType | default "PathPrefix" }}
            value: {{ .Values.httpRoute.pathPrefix }}
      {{- if or .Values.httpRoute.cors .Values.httpRoute.headers }}
      filters:
{{- include "workbench.lib.httpRoute.filters" . | nindent 8 }}
      {{- end }}
{{- include "workbench.lib.httpRoute.timeouts" . }}
      backendRefs:
{{- include "workbench.lib.httpRoute.backendRefs" . | nindent 0 }}
{{- end }}
{{- end -}}
