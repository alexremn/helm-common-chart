{{/*
=============================================================================
HELPER FUNCTIONS
This file contains utility functions for configs, secrets, and other operations.
=============================================================================
*/}}

{{/*
Generate a random hexadecimal string of a specified length.
Usage: {{ include "randHex" 16 }}
*/}}
{{- define "randHex" -}}
    {{- $base := "0123456789abcdef" -}}
    {{- $result := "" -}}
    {{- range $i := until . -}}
        {{- /* `randNumeric 1` returns "0".."9" — never picks a..f. Pick over
               the full 0..15 range by drawing a 6-digit number and reducing
               mod 16. Per-character bias is ~0.0016% (1,000,000 mod 16 = 0,
               so bias is actually zero for this range size). */ -}}
        {{- $idx := mod (randNumeric 6 | int) 16 | int -}}
        {{- $result = print $result (substr $idx (add $idx 1 | int) $base) -}}
    {{- end -}}
    {{- $result -}}
{{- end -}}

{{/*
=============================================================================
CONFIG OPERATORS
=============================================================================
*/}}

{{/*
Define a config value, with lookup for existing values
Usage: {{ include "config.define" (dict "name" "config-name" "key" "KEY_NAME" "value" "default-value" "ns" .Release.Namespace) }}
*/}}
{{- define "config.define" -}}
  {{- $name       := default "config" .name -}}
  {{- $key        := required "Key is required" .key -}}
  {{- $namespace  := .ns | default "" -}}
  {{- $value      := .value -}}
  {{- $configMap  := (lookup "v1" "ConfigMap" $namespace $name).data -}}
  {{- if and $configMap (index $configMap $key) -}}
    {{- $value = index $configMap $key -}}
  {{- end -}}
  {{- printf "%s: %s" $key ($value | toString | quote) -}}
{{- end -}}

{{/*
=============================================================================
SECRET OPERATORS
=============================================================================
*/}}

{{/*
Generate external secret data entries
Usage: {{ include "secrets.generate" (dict "key" "secret-key" "values" (list "property1" "property2")) }}
*/}}
{{- define "secrets.generate" -}}
{{- $key := .key -}}
{{- range $value := .values }}
  - secretKey: {{ $value }}
    remoteRef:
      key: {{ $key }}
      property: {{ $value }}
{{- end -}}
{{- end -}}

{{/*
Retrieve a secret value from Kubernetes.

Resolution is offline / Helm-only: uses the `lookup` template function,
which only sees Secrets that already exist in the target cluster at the
time `helm template`/`upgrade` runs. There is no fetch against an
external secret store (AWS Secrets Manager, Vault, ESO etc.); for that
flow see `secrets.retrieve.external` or the ExternalSecret renderer.

If the Secret does not exist, an empty string (or `KEY: ""` when
`type=full`) is returned silently — `helm install --dry-run` will not
fail. This is intentional for bootstrapping new clusters; callers that
need the value to exist must guard externally.

Usage: {{ include "secrets.retrieve" (dict "name" "secret-name" "key" "KEY_NAME" "type" "full" "ns" .Release.Namespace) }}
*/}}
{{- define "secrets.retrieve" -}}
  {{- $type       := default "full" .type -}}
  {{- $name       := default "secrets" .name -}}
  {{- $key        := required "Key is required" .key -}}
  {{- $namespace  := .ns | default "" -}}
  {{- $secret     := (lookup "v1" "Secret" $namespace $name).data -}}
  {{- if and $secret (index $secret $key) -}}
    {{- $value := index $secret $key | b64dec -}}
    {{- if eq $type "full" -}}
      {{- printf "%s: %s" $key ($value | toString | quote) -}}
    {{- else if eq $type "value" -}}
      {{- $value -}}
    {{- end -}}
  {{- else -}}
    {{- if eq $type "full" -}}
      {{- printf "%s: %s" $key "" -}}
    {{- else if eq $type "value" -}}
      {{- "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Define a secret value with generator and lookup capability.

Like `secrets.retrieve`, the lookup is offline / Helm-only and only
resolves against Secrets already present in the cluster. If the Secret
does not exist, a generated value is emitted (random 64-char alphanum
when `var=base`; random hex when `var=hex`) — and that generated value
will *change on every render*, so consuming workloads will see token
drift unless the underlying Secret is created before the next upgrade.

Use this for first-install bootstrap of secrets that the cluster will
then own. Do not use as a long-running source of truth.

Usage: {{ include "secrets.define" (dict "name" "secret-name" "key" "KEY_NAME" "value" "default-value" "type" "full" "var" "base" "ns" .Release.Namespace) }}
*/}}
{{- define "secrets.define" -}}
  {{- $type       := default "full" .type -}}
  {{- $var        := default "base" .var -}}
  {{- $name       := default "secrets" .name -}}
  {{- $key        := required "Key is required" .key -}}
  {{- $namespace  := .ns | default "" -}}
  {{- $value      := .value -}}
  {{- if or (not $value) (eq $value "") -}}
    {{- if eq $var "base" -}}
      {{- $value = randAlphaNum 64 -}}
    {{- else if eq $var "hex" -}}
      {{- $value = (include "randHex" 64) -}}
    {{- end -}}
  {{- end -}}
  {{- if and $key $name -}}
    {{- $secret := (lookup "v1" "Secret" $namespace $name).data -}}
    {{- if and $secret (index $secret $key) -}}
      {{- $value := index $secret $key | b64dec -}}
      {{- if eq $type "full" -}}
        {{- printf "%s: %s" $key ($value | toString | quote) -}}
      {{- else if eq $type "value" -}}
        {{- $value -}}
      {{- end -}}
    {{- else -}}
      {{- if eq $type "full" -}}
        {{- printf "%s: %s" $key ($value | toString | quote) -}}
      {{- else if eq $type "value" -}}
        {{- $value -}}
      {{- end -}}
    {{- end -}}
  {{- else -}}
    {{- if eq $type "full" -}}
      {{- printf "%s: %s" $key ($value | toString | quote) -}}
    {{- else if eq $type "value" -}}
      {{- $value -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Retrieve a secret across namespaces with fallback support
Usage: {{ include "secrets.retrieve.external" (dict "key" "KEY_NAME" "base" (dict "name" "base-secret" "ns" "default") "ext" (dict "name" "external-secret" "ns" "external-ns")) }}
*/}}
{{- define "secrets.retrieve.external" -}}
  {{- $key                := required "Key is required" .key -}}
  {{- $nameBase           := default "secrets" .base.name -}}
  {{- $namespaceBase      := .base.ns -}}
  {{- $secretBase         := (lookup "v1" "Secret" $namespaceBase $nameBase).data -}}
  {{- $nameExt            := default "secrets" .ext.name -}}
  {{- $namespaceExternal  := .ext.ns -}}
  {{- $secretExternal     := (lookup "v1" "Secret" $namespaceExternal $nameExt).data -}}
  {{- if and $secretBase (index $secretBase $key) -}}
    {{- $value := index $secretBase $key | b64dec -}}
    {{- printf "%s: %s" $key ($value | toString | quote) -}}
  {{- else if and $secretExternal (index $secretExternal $key) -}}
    {{- $value := index $secretExternal $key | b64dec -}}
    {{- printf "%s: %s" $key ($value | toString | quote) -}}
  {{- else -}}
    {{- printf "%s: %s" $key "" -}}
  {{- end -}}
{{- end -}}

{{/*
Build a merged securityContext map for the requested scope ("pod" or
"container"). Used by `common.pod.securityContext` and
`common.container.securityContext`; both share the merge logic and
differ only in scope key and the set of override keys.

Returns the YAML-marshaled merged map (use `fromYaml` to consume).

Parameters:
  scope         — "pod" or "container"
  root          — chart root (for security posture + global lookups)
  component     — component values map (reads .securityContext.<scope>)
  input         — for the legacy unwrapped call shape, the raw input
                  map whose top-level <overrideKeys> are layered last
  overrideKeys  — list of top-level keys honored on unwrapped input
  wrapped       — true when called with the new dict shape (skips
                  the override-keys layering)
*/}}
{{- define "common._securityContext.merge" -}}
{{- $scope := required "common._securityContext.merge: scope is required" .scope -}}
{{- $root := default dict .root -}}
{{- $component := default dict .component -}}
{{- $input := default dict .input -}}
{{- $overrideKeys := default (list) .overrideKeys -}}
{{- $wrapped := default false .wrapped -}}
{{- $secCtx := dict -}}
{{- $security := include "common.security" $root -}}
{{- $secDefaults := index (include "common.security.defaults" $root | fromYaml) $security -}}
{{- if kindIs "map" $secDefaults -}}
  {{- $_ := mergeOverwrite $secCtx (deepCopy (dig $scope dict $secDefaults)) -}}
{{- end -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $globalSecCtx := dig "global" "securityContext" $scope dict $values -}}
{{- if kindIs "map" $globalSecCtx -}}
  {{- $_ := mergeOverwrite $secCtx (deepCopy $globalSecCtx) -}}
{{- end -}}
{{- if and (kindIs "map" $component) (hasKey $component "securityContext") -}}
  {{- $compSec := $component.securityContext -}}
  {{- if and (kindIs "map" $compSec) (hasKey $compSec $scope) (kindIs "map" (index $compSec $scope)) -}}
    {{- $_ := mergeOverwrite $secCtx (deepCopy (index $compSec $scope)) -}}
  {{- end -}}
{{- end -}}
{{- if and (not $wrapped) (kindIs "map" $input) -}}
  {{- range $key := $overrideKeys -}}
    {{- if hasKey $input $key -}}
      {{- $_ := set $secCtx $key (index $input $key) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{ toYaml $secCtx }}
{{- end -}}

{{/*
Emit a YAML field from a source map, conditionally.

Replaces the "if hasKey emit toYaml" passthrough boilerplate scattered
across container/pod helpers. Skips emission entirely when the source
map does not have the key.

Parameters:
  src      — source dict (typically a component values map)
  key      — key to look up in src
  emitAs   — output field name (defaults to key)
  scalar   — true to emit `field: <value>` instead of `field: |yaml|`
             (use for primitives like priorityClassName)

Usage:
  {{- include "common.passthroughField" (dict "src" . "key" "lifecycle") }}
  {{- include "common.passthroughField" (dict "src" . "key" "priorityClassName" "scalar" true) }}
*/}}
{{- define "common.passthroughField" -}}
{{- $src := .src -}}
{{- $key := required "common.passthroughField: key is required" .key -}}
{{- $emitAs := default $key .emitAs -}}
{{- $scalar := default false .scalar -}}
{{- if and (kindIs "map" $src) (hasKey $src $key) -}}
{{- $val := index $src $key }}
{{- if $scalar }}
{{ $emitAs }}: {{ $val | quote }}
{{- else }}
{{ $emitAs }}: {{ toYaml $val | nindent 2 }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the ServiceAccount name for a component.

Single source of truth for both the pod side (`spec.serviceAccountName`)
and the RBAC side (RoleBinding/ClusterRoleBinding `subjects[].name`).
The two must agree; resolving them through this helper prevents the
pod-side literal `"default"` from drifting away from the RBAC-side
`dig "serviceAccount" "name" $cmp` resolution.

Usage:
  {{ include "common.serviceAccountName" (dict "component" .componentValues "fallback" $cmp) }}

Resolution order:
  1. .component.serviceAccount.name (explicit override)
  2. .fallback (caller-supplied default, typically the component name)
*/}}
{{- define "common.serviceAccountName" -}}
{{- $component := default dict .component -}}
{{- $fallback := required "common.serviceAccountName: fallback is required" .fallback -}}
{{- dig "serviceAccount" "name" $fallback $component -}}
{{- end -}}

{{/*
Deterministic resource name "<name>-<suffix>". Unlike `common.generateName`
(which is RANDOM), this is STABLE across renders and REQUIRES an explicit
`suffix` — pass `.Release.Revision` for a per-revision name. Use for Job /
CronJob names that must not churn on every `helm upgrade`.
Usage: {{ include "generateName" (dict "name" "migrate" "suffix" .Release.Revision) }}
*/}}
{{- define "generateName" -}}
  {{- $name := required "Name is required" .name }}
  {{- $suffix := .suffix }}
  {{- if not $suffix }}
    {{- $suffix = required "generateName: suffix is required (pass .Release.Revision for a per-revision suffix, or any deterministic string)" .suffix }}
  {{- end }}
  {{- printf "%s-%s" $name (toString $suffix) }}
{{- end -}}
