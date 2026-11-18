{{/*
Common labels for all chart-managed resources.
*/}}
{{- define "lezepplean.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "lezepplean.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels: used in spec.selector.matchLabels (immutable!) and the pod template.
Must stay stable across chart upgrades.
*/}}
{{- define "lezepplean.selectorLabels" -}}
app.kubernetes.io/name: lezepplean
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
