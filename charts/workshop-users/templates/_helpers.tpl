{{- define "workshop.users" -}}
{{- if .Values.users.explicitNames }}
{{- toYaml .Values.users.explicitNames -}}
{{- else -}}
{{- $prefix := .Values.users.prefix | default "user" -}}
{{- range $i := untilStep 1 (int (add1 (.Values.users.count | int))) 1 }}
- {{ printf "%s%d" $prefix $i | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{- define "workshop.labels" -}}
app.kubernetes.io/name: workshop-users
app.kubernetes.io/part-of: inner-outer-loop-workshop
app.kubernetes.io/managed-by: argocd
{{- end -}}
