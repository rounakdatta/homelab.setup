{{- define "applet.labels" -}}
app.kubernetes.io/name: applet
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: applet
{{- end -}}

{{- define "applet.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}

{{- define "applet.secretName" -}}
{{- if .Values.secret.create -}}
{{ .Release.Name }}
{{- else -}}
{{ .Values.secret.existingSecret }}
{{- end -}}
{{- end -}}

{{- define "applet.phoneArch" -}}
{{- if gt (len .Values.phones) 0 -}}
{{ (index .Values.phones 0).arch | default "amd64" }}
{{- else -}}amd64{{- end -}}
{{- end -}}

{{/* The first phone's ABIs, comma-joined; empty when it sets none. */}}
{{- define "applet.phoneAbis" -}}
{{- if gt (len .Values.phones) 0 -}}
{{ join "," ((index .Values.phones 0).abis | default list) }}
{{- end -}}
{{- end -}}
