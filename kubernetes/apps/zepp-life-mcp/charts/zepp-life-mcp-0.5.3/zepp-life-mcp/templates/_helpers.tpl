{{- define "zepp-life-mcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "zepp-life-mcp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "zepp-life-mcp.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "zepp-life-mcp.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "zepp-life-mcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zepp-life-mcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "zepp-life-mcp.claimName" -}}
{{- if .Values.persistence.existingClaim }}{{ .Values.persistence.existingClaim }}{{ else }}{{ include "zepp-life-mcp.fullname" . }}-data{{ end }}
{{- end }}

{{/* Env shared by the server and the sync job: same config, same database. */}}
{{- define "zepp-life-mcp.commonEnv" -}}
- name: ZEPP_MODE
  value: {{ .Values.zepp.mode | quote }}
- name: ZEPP_REGION
  value: {{ .Values.zepp.region | quote }}
- name: ZEPP_TIMEZONE
  value: {{ .Values.zepp.timezone | quote }}
- name: ZEPP_DATABASE_PATH
  value: {{ printf "%s/zepp_life.db" .Values.persistence.mountPath | quote }}
- name: ZEPP_STORE_RAW_PAYLOADS
  value: {{ .Values.zepp.storeRawPayloads | quote }}
- name: XDG_DATA_HOME
  value: {{ .Values.persistence.mountPath | quote }}
- name: XDG_CONFIG_HOME
  value: {{ printf "%s/config" .Values.persistence.mountPath | quote }}
{{- if .Values.zepp.userId }}
- name: ZEPP_USER_ID
  value: {{ .Values.zepp.userId | quote }}
{{- end }}
- name: ZEPP_APP_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.zepp.existingSecret }}
      key: {{ .Values.zepp.secretKeys.apptoken }}
{{- end }}
