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
app.kubernetes.io/name: workshop-platform
app.kubernetes.io/part-of: inner-outer-loop-workshop
app.kubernetes.io/managed-by: argocd
{{- end -}}

{{/*
PodMonitor that scrapes the Envoy sidecars (and gateways) of one namespace.
Usage: include "workshop.istioProxyPodMonitor" (dict "namespace" "ns" "root" $)
*/}}
{{- define "workshop.istioProxyPodMonitor" -}}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: istio-proxies-monitor
  namespace: {{ .namespace | quote }}
  labels:
    {{- include "workshop.labels" .root | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  selector:
    matchExpressions:
      - key: istio-prometheus-ignore
        operator: DoesNotExist
  podMetricsEndpoints:
    - path: /stats/prometheus
      interval: 30s
      relabelings:
        - action: keep
          sourceLabels: ["__meta_kubernetes_pod_container_name"]
          regex: istio-proxy
        - action: keep
          sourceLabels: ["__meta_kubernetes_pod_annotationpresent_prometheus_io_scrape"]
        - action: replace
          regex: (\d+);(([A-Fa-f0-9]{1,4}::?){1,7}[A-Fa-f0-9]{1,4})
          replacement: "[$2]:$1"
          sourceLabels: ["__meta_kubernetes_pod_annotation_prometheus_io_port", "__meta_kubernetes_pod_ip"]
          targetLabel: __address__
        - action: replace
          regex: (\d+);((([0-9]+?)(\.|$)){4})
          replacement: "$2:$1"
          sourceLabels: ["__meta_kubernetes_pod_annotation_prometheus_io_port", "__meta_kubernetes_pod_ip"]
          targetLabel: __address__
        - action: labeldrop
          regex: __meta_kubernetes_pod_label_(.+)
        - sourceLabels: ["__meta_kubernetes_namespace"]
          action: replace
          targetLabel: namespace
        - sourceLabels: ["__meta_kubernetes_pod_name"]
          action: replace
          targetLabel: pod_name
{{- end -}}
