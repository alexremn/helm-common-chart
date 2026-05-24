{{/*
=============================================================================
PROMETHEUS SHARED HELPERS
Helpers shared between Prometheus Operator monitors (ServiceMonitor and
PodMonitor). Kept in common/ so neither monitor template depends on the
other — each can be rendered or removed independently while still sharing
identical endpoint-level logic.
=============================================================================
*/}}

{{/*
Render the metricRelabelings block (with profile fallback) of a
ServiceMonitor or PodMonitor endpoint. Identical logic for both kinds.

Emits nothing when both explicit and profile are empty.

Usage (must be invoked with `{{- ... -}}` whitespace trimming):
  {{- include "common.prometheus.metricRelabelings" (dict
        "explicit" $cfg.metricRelabelings
        "profile" $profileRelabelings) -}}
*/}}
{{- define "common.prometheus.metricRelabelings" -}}
{{- $explicit := .explicit -}}
{{- $profile := .profile -}}
{{- if $explicit }}
      metricRelabelings: {{ toYaml $explicit | nindent 8 }}
{{- else if $profile }}
      metricRelabelings:
{{ $profile | indent 8 }}
{{- end -}}
{{- end -}}
