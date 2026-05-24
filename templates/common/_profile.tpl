{{/*
=============================================================================
PROFILE HELPERS
Resolves the active profile name and exposes a profile-keyed defaults map.

Profiles let helpers swap previously-hardcoded literals for a lookup. The
`generic` profile (default in v2.x) ships vanilla K8s defaults. The
`rails` profile is opt-in via `global.profile: rails` for charts
upgrading from v1.x. `python` and `go` profiles cover other common
runtimes. See docs/profiles.md.
=============================================================================
*/}}

{{/*
Resolve the active profile name.

Lookup order (per-component override, v2.1+):
  1. <component>.profile          (per-workload override)
  2. .Values.global.profile       (chart-wide default)
  3. literal "generic"            (vanilla K8s defaults; set
                                   `global.profile: rails` to retain
                                   v1.x behavior)

Callers may pass either:
  - legacy: a root context (carries `.Values`). Resolves to
    `Values.global.profile > "generic"`. Preserves v2.0 behavior.
  - new:    a dict `(dict "root" $root "component" $componentValues)`.
    Resolves the per-component override first, falling back to
    `Values.global.profile`, then `"generic"`.

Validation: result must be one of `generic|rails|python|go`. Invalid
values fail loudly at render time so misconfiguration never silently
falls through to a "default" profile.
*/}}
{{- define "common.profile" -}}
{{- $root := . -}}
{{- $component := dict -}}
{{- if and (kindIs "map" .) (hasKey . "root") (or (hasKey . "component") (hasKey . "componentValues")) -}}
  {{- $root = default dict .root -}}
  {{- if hasKey . "component" -}}
    {{- $component = default dict .component -}}
  {{- else -}}
    {{- $component = default dict .componentValues -}}
  {{- end -}}
{{- end -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $globalProfile := dig "global" "profile" "generic" $values -}}
{{- $profile := $globalProfile -}}
{{- if and (kindIs "map" $component) (hasKey $component "profile") -}}
  {{- $cmpProfile := index $component "profile" -}}
  {{- if and (kindIs "string" $cmpProfile) (ne $cmpProfile "") -}}
    {{- $profile = $cmpProfile -}}
  {{- end -}}
{{- end -}}
{{- $valid := list "generic" "rails" "python" "go" -}}
{{- if not (has $profile $valid) -}}
{{- fail (printf "Unknown profile %q. Valid profiles: %s." $profile (join ", " $valid)) -}}
{{- end -}}
{{- $profile -}}
{{- end -}}

{{/*
Profile defaults map. Returns a YAML literal keyed by profile name. Helpers
consume it via:
  {{- $profile := include "common.profile" (dict "root" $ "component" $componentValues) -}}
  {{- $defaults := index (include "common.profile.defaults" $ | fromYaml) $profile -}}

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
    command: []
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
  securityContext:
    pod:
      seccompType: RuntimeDefault
    container:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
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
  securityContext:
    pod:
      seccompType: RuntimeDefault
    container:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
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
  securityContext:
    pod:
      seccompType: RuntimeDefault
    container:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
{{- end -}}
