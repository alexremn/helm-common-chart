{{/*
=============================================================================
PROFILE HELPERS
Resolves the active profile name and exposes a profile-keyed defaults map.

Profiles let helpers swap previously-hardcoded literals for a lookup. The
`generic` profile (default) ships vanilla K8s defaults. The `rails` profile
is opt-in via `global.profile: rails` for charts upgrading from v1.x.
`python` and `go` profiles cover other common runtimes. See docs/profiles.md.

Security posture is a SEPARATE axis — see `common.security` below and the
`global.security` flag (`minimal` | `generic`). Profiles no longer carry a
securityContext.
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
    `Values.global.profile > "generic"`.
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

{{/*
=============================================================================
SECURITY POSTURE
A standalone axis, independent of the runtime profile. Controls the default
pod/container securityContext only. Selected via `global.security`:

  minimal  (default)  — baseline-hardened: allowPrivilegeEscalation:false +
                        capabilities.drop:[ALL] (overridable). runAsNonRoot /
                        readOnlyRootFilesystem stay opt-in so charts that write
                        to disk or run as root still work out of the box.
                        Pod-level seccompProfile stays RuntimeDefault.
  generic             — hardened: runAsNonRoot, allowPrivilegeEscalation:false,
                        readOnlyRootFilesystem, drop-ALL capabilities.

Both postures are overridable per-scope by `global.securityContext.<scope>`
and `<component>.securityContext.<scope>` (layered after, last wins). See
`common._securityContext.merge`.
=============================================================================
*/}}

{{/*
Resolve the active security posture name. Takes a root context (carries
`.Values`). Result must be one of `minimal|generic`; invalid values fail
loudly at render time.
*/}}
{{- define "common.security" -}}
{{- $root := . -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $security := dig "global" "security" "minimal" $values -}}
{{- $valid := list "minimal" "generic" -}}
{{- if not (has $security $valid) -}}
{{- fail (printf "Unknown security posture %q. Valid postures: %s." $security (join ", " $valid)) -}}
{{- end -}}
{{- $security -}}
{{- end -}}

{{/*
Security posture defaults map. Returns a YAML literal keyed by posture name,
each carrying `pod` and `container` securityContext scopes. Consumed by
`common._securityContext.merge`.
*/}}
{{- define "common.security.defaults" -}}
minimal:
  pod:
    seccompType: RuntimeDefault
  container:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
generic:
  pod:
    # Pod-level runAsNonRoot is inherited by every container (init + sidecars
    # included) unless a container overrides it — defense in depth on top of
    # the container-scope setting below.
    runAsNonRoot: true
    seccompType: RuntimeDefault
  container:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
{{- end -}}
