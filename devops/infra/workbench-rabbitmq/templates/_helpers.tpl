{{/*
RabbitMQ diagnostics probe shared by startup, readiness, and liveness checks.
*/}}
{{- define "workbench-rabbitmq.probe" -}}
exec:
  command:
    {{- toYaml .root.Values.probes.command | nindent 4 }}
{{- with .settings }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}
