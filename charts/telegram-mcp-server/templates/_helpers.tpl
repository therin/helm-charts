{{- define "telegram-mcp-server.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "telegram-mcp-server.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "telegram-mcp-server.labels" -}}
app.kubernetes.io/name: {{ include "telegram-mcp-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "telegram-mcp-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "telegram-mcp-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "telegram-mcp-server.secretName" -}}
{{- if .Values.telegram.existingSecret }}
{{- .Values.telegram.existingSecret }}
{{- else }}
{{- include "telegram-mcp-server.fullname" . }}-secret
{{- end }}
{{- end }}
