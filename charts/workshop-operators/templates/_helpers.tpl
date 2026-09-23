{{- define "workshop.labels" -}}
app.kubernetes.io/name: workshop-operators
app.kubernetes.io/part-of: inner-outer-loop-workshop
app.kubernetes.io/managed-by: argocd
{{- end -}}

{{/* Enabled subscriptions as a list of dicts. */}}
{{- define "workshop.enabledSubscriptions" -}}
{{- $out := list -}}
{{- range $key := keys .Values.subscriptions | sortAlpha -}}
{{- $sub := index $.Values.subscriptions $key -}}
{{- if $sub.enabled -}}
{{- $out = append $out $sub -}}
{{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}
