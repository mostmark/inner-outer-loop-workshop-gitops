{{- define "workshop.labels" -}}
app.kubernetes.io/name: workshop
app.kubernetes.io/part-of: inner-outer-loop-workshop
app.kubernetes.io/managed-by: argocd
{{- end -}}

{{/*
Values for a component chart: the shared users block plus the component's own overrides.
*/}}
{{- define "workshop.componentValues" -}}
{{- $root := index . 0 -}}
{{- $overrides := index . 1 | default dict -}}
{{- $values := deepCopy $overrides -}}
{{- $_ := set $values "users" $root.Values.users -}}
{{- toYaml $values -}}
{{- end -}}
