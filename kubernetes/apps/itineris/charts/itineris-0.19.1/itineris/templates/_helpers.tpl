{{/*
Common labels for all chart-managed resources.
*/}}
{{- define "itineris.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "itineris.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels -- used in spec.selector.matchLabels (immutable!) and pod template.
Must remain stable across chart upgrades. Adding labels here forces resource recreation.
*/}}
{{- define "itineris.selectorLabels" -}}
app.kubernetes.io/name: itineris
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
The admin gets a different app.kubernetes.io/name so its pods can never be
selected by the public Service, and the public selector above stays untouched
(changing it would force a Deployment recreate).
*/}}
{{- define "itineris.adminSelectorLabels" -}}
app.kubernetes.io/name: itineris-admin
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "itineris.adminLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "itineris.adminSelectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Image references. An empty tag falls back to Chart.appVersion.
*/}}
{{- define "itineris.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}
{{- define "itineris.adminImage" -}}
{{ .Values.admin.image.repository }}:{{ .Values.admin.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "itineris.claimName" -}}
{{ .Values.persistence.existingClaim | default (printf "%s-data" .Release.Name) }}
{{- end }}
