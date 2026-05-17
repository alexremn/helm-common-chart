{{/*
=============================================================================
PROFILE HELPERS
Resolves the active profile name and exposes a profile-keyed defaults map.

Profiles let helpers swap previously-hardcoded literals for a lookup. The
`rails` profile (default) preserves all v1.3.1 behavior. `generic`, `python`,
and `go` profiles substitute vanilla K8s defaults. See docs/profiles.md.
=============================================================================
*/}}

{{/*
Resolve the active profile name.
Lookup order:
  1. .Values.global.profile
  2. literal "rails" (preserves v1.3.1 behavior for charts that haven't opted in)
*/}}
{{- define "common.profile" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- dig "global" "profile" "rails" $values -}}
{{- end -}}

{{/*
Profile defaults map. Returns a YAML literal keyed by profile name. Helpers
consume it via:
  {{- $profile := include "common.profile" . -}}
  {{- $defaults := index (include "common.profile.defaults" . | fromYaml) $profile -}}

Carries Rails-flavored defaults that need to flip when the profile changes,
plus shared K8s defaults that we expose here so future profiles (and
chart-wide global overrides) can change them centrally without per-helper
code edits.
*/}}
{{- define "common.profile.defaults" -}}
rails:
  probe:
    type: http
    path: /health_check/full
    command:
      - cat
      - /app/tmp/sidekiq_readiness_probe
    port: http
    initialDelaySeconds: 0
    periodSeconds: 10
    failureThreshold: 5
    timeoutSeconds: 3
  podMonitor:
    # Stored as a YAML block scalar so consumers can emit it byte-identically
    # to the v1.3.1 hardcoded text — single-quoted regex, flow-style sourceLabels.
    # Round-tripping a structured list through fromYaml + toYaml would drop the
    # single quotes and switch the list to block style.
    metricRelabelings: |-
      - action: drop
        regex: '(activerecord_query_duration_seconds_bucket|http_response_duration_milliseconds_bucket|rails_view_runtime_seconds_bucket|rails_request_duration_seconds_bucket|rails_db_runtime_seconds_bucket)'
        sourceLabels: [__name__]
  envFrom:
    defaultConfigName: config
    defaultSecretName: secrets
  service:
    type: ClusterIP
  pvc:
    accessMode: ReadWriteOnce
  securityContext:
    pod:
      runAsUser: 1000
      runAsGroup: 3000
      seccompType: RuntimeDefault
    container:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
generic:
  probe:
    type: http
    path: /healthz
    command: []
    port: http
    initialDelaySeconds: 0
    periodSeconds: 10
    failureThreshold: 3
    timeoutSeconds: 1
  podMonitor:
    metricRelabelings: ""
  envFrom:
    defaultConfigName: ""
    defaultSecretName: ""
  service:
    type: ClusterIP
  pvc:
    accessMode: ReadWriteOnce
python:
  probe:
    type: http
    path: /health
    command: []
    port: http
    initialDelaySeconds: 0
    periodSeconds: 10
    failureThreshold: 3
    timeoutSeconds: 2
  podMonitor:
    metricRelabelings: ""
  envFrom:
    defaultConfigName: ""
    defaultSecretName: ""
  service:
    type: ClusterIP
  pvc:
    accessMode: ReadWriteOnce
go:
  probe:
    type: http
    path: /healthz
    command: []
    port: http
    initialDelaySeconds: 0
    periodSeconds: 10
    failureThreshold: 3
    timeoutSeconds: 1
  podMonitor:
    metricRelabelings: ""
  envFrom:
    defaultConfigName: ""
    defaultSecretName: ""
  service:
    type: ClusterIP
  pvc:
    accessMode: ReadWriteOnce
{{- end -}}
