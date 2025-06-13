{{- define "loco.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "loco.namespace" -}}
{{- default .Values.namespace .Release.Namespace -}}
{{- end -}}

{{- define "loco.image" -}}
{{- $root := .root -}}
{{- $image := .image -}}
{{- $tag := .tag | default "latest" -}}
{{- $repo := $root.Values.imageRepo | default "" -}}
{{- if $repo -}}
{{- $repo | trimSuffix "/" }}/{{ $image }}:{{ $tag }}
{{- else -}}
{{- $image }}:{{ $tag }}
{{- end -}}
{{- end -}}
