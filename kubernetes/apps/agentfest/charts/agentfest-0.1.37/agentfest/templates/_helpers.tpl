{{/*
Common labels for all chart-managed resources.
*/}}
{{- define "agentfest.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "agentfest.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used in spec.selector.matchLabels (immutable!) and pod template.
Must remain stable across chart upgrades. Adding labels here forces resource recreation.
*/}}
{{- define "agentfest.selectorLabels" -}}
app.kubernetes.io/name: agentfest
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
