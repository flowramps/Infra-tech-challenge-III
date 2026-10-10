{{- define "sample-app.labels" -}}
app.kubernetes.io/part-of: sample-app
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version }}
{{- end }}

{{- define "sample-app.podLabels" -}}
app: {{ .name }}
app.kubernetes.io/name: {{ .name }}
version: {{ .version }}
{{- end }}
