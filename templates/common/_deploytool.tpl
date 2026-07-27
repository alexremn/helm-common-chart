{{/*
=============================================================================
DEPLOY-TOOL DIALECT
Resolves which tool consumes the rendered manifests, and emits the ordering
and lifecycle metadata that tool understands.
=============================================================================
*/}}

{{/*
Resolve the active deploy tool.

Resolution order:
  1. .Values.global.deployTool           — explicit, validated
  2. .Values.global.werf.annotations     — deprecated boolean override
                                           (true -> werf, false -> generic)
  3. werf service values present         -> werf
  4. "generic"

werf injects its own service values on every deploy: `global.werf.version` and
`global.werf.name` always, `global.werf.env` when --env/$WERF_ENV is set, plus
a `werf` top-level map. Charts migrated from werf 1.x also hand-write
`werf.name` / `werf.env`; the bare presence of a `werf` key covers both.

ArgoCD cannot be detected: Helm exposes no `env` function, and nothing in
.Release or .Capabilities distinguishes ArgoCD's repo-server from a plain
`helm template`. ArgoCD consumers set global.deployTool explicitly, normally
once in an ApplicationSet template.

Usage: {{- $tool := include "common.deployTool" $ -}}
*/}}
{{- define "common.deployTool" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $valid := list "generic" "werf" "argocd" -}}
{{- $explicit := dig "global" "deployTool" "" $values -}}
{{- $legacy := dig "global" "werf" "annotations" nil $values -}}
{{- if $explicit -}}
  {{- if not (has $explicit $valid) -}}
    {{- fail (printf "Unknown global.deployTool %q. Valid values: %s." $explicit (join ", " $valid)) -}}
  {{- end -}}
  {{- $explicit -}}
{{- else if not (kindIs "invalid" $legacy) -}}
  {{- ternary "werf" "generic" (eq $legacy true) -}}
{{- else if or (dig "global" "werf" "version" nil $values) (dig "global" "werf" "name" nil $values) (hasKey $values "werf") -}}
werf
{{- else -}}
generic
{{- end -}}
{{- end -}}

{{/*
Deploy-ordering annotation for the active dialect.

werf orders with `werf.io/weight`, ArgoCD with
`argocd.argoproj.io/sync-wave`. Both are lower-runs-first integers, so the
weight maps 1:1. Plain Helm needs nothing — its install order already puts
ConfigMaps and Secrets ahead of workloads.

Usage:
  {{- include "common.annotations.ordering" (dict "root" . "weight" -1) }}
*/}}
{{- define "common.annotations.ordering" -}}
{{- $tool := include "common.deployTool" .root -}}
{{- $weight := .weight | toString -}}
{{- if eq $tool "werf" -}}
werf.io/weight: {{ $weight | quote }}
{{- else if eq $tool "argocd" -}}
argocd.argoproj.io/sync-wave: {{ $weight | quote }}
{{- end -}}
{{- end -}}

{{/*
Workload lifecycle / rollout-tracking annotations for the active dialect.

werf tracks rollouts with `werf.io/no-activity-timeout` and
`werf.io/failures-allowed-per-replica`. ArgoCD has no per-resource
equivalent — retry patience lives in Application.spec.syncPolicy.retry — and
plain Helm has none either, so both emit nothing.

Usage:
  {{- include "common.annotations.lifecycle" $root }}
*/}}
{{- define "common.annotations.lifecycle" -}}
{{- if eq (include "common.deployTool" .) "werf" -}}
werf.io/no-activity-timeout: {{ default "6m" .timeout | quote }}
werf.io/failures-allowed-per-replica: {{ default "3" .failures | quote }}
{{- end -}}
{{- end -}}

{{/*
Refuse a cluster-dependent or non-deterministic operation under ArgoCD.

ArgoCD's repo-server renders with `helm template` and no Kubernetes API
access, so Helm's `lookup` always returns an empty dict. Helpers that fall
back to a generated or empty value therefore either rotate credentials on
every reconcile or apply empty data over live cluster material.

Escape hatch: `global.argocd.allowClusterlessLookups: true`, so blanking or
regenerating live data is always a deliberate, greppable choice.

Usage:
  {{- include "common.argocd.requireCluster" (dict
        "root" $ctx
        "helper" "secrets.define"
        "detail" "pass an explicit `value`, or manage the secret with chart.extsecret") }}
*/}}
{{- define "common.argocd.requireCluster" -}}
{{- $root := .root -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- if eq (include "common.deployTool" $root) "argocd" -}}
{{- if not (dig "global" "argocd" "allowClusterlessLookups" false $values) -}}
{{- fail (printf "%s requires a cluster lookup, which is unavailable under global.deployTool: argocd (ArgoCD renders with `helm template`, so Helm's `lookup` always returns empty and this helper would emit a regenerated or empty value over live cluster data). %s. To keep the current behaviour anyway, set global.argocd.allowClusterlessLookups: true." .helper .detail) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Whether consumer-supplied content is rendered through Helm `tpl`.

Default true under generic/werf. Default false under argocd: `tpl` executes
arbitrary consumer template text, so `{{ now }}` or `{{ uuidv4 }}` in a value
re-renders on every reconcile — permanent OutOfSync for a ConfigMap or
ScaledObject, and a rolling restart of every replica when it reaches a pod
template under selfHeal.

Overrides: global.tpl.envValues (chart-wide), <cmp>.envRaw: true (per-component,
forces off).

Usage:
  {{- $tplEnabled := eq (include "common.tpl.enabled" (dict "root" $ "component" $componentValues)) "true" }}
*/}}
{{- define "common.tpl.enabled" -}}
{{- $values := include "common._values" .root | fromYaml | default dict -}}
{{- $default := ne (include "common.deployTool" .root) "argocd" -}}
{{- $enabled := dig "global" "tpl" "envValues" $default $values -}}
{{- if dig "envRaw" false (default dict .component) -}}{{- $enabled = false -}}{{- end -}}
{{- ternary "true" "false" (eq $enabled true) -}}
{{- end -}}

{{/*
Merge chart-wide `global.annotations`, a chart-emitted default block, and a
resource's own annotations into ONE map, so a caller no longer has to emit
two separate YAML blocks that collide into a duplicate mapping key whenever
`global.annotations` (or the resource's own annotations) repeats a key the
chart already emits (e.g. `argocd.argoproj.io/sync-wave`,
`argocd.argoproj.io/sync-options`) — the bug `eccbb27` fixed for
`common.workload.annotations` only.

Returns the YAML body only (no leading `annotations:` key), matching
`common.annotations`. The caller emits the key, gated on non-empty output.

Precedence (lowest to highest): `global.annotations` < `defaults` <
the resource's own `annotations`.

`argocd.argoproj.io/sync-options` is a comma-separated LIST, not a scalar —
overwriting it on collision would silently drop the chart's own
`Prune=false` retention guarantee. It is therefore always merged by taking
the union of the comma-separated entries across all three layers (in
precedence order, de-duplicated), never overwritten.

Parameters:
  root        — chart root (or an ancestor dict carrying .Values, matching
                common._values)
  defaults    — optional chart-emitted defaults: either the YAML text
                another helper returned (e.g. common.annotations.retain,
                config.annotations.default) or a plain map
  annotations — the resource's own annotations map (highest precedence)

Usage:
  {{- $ann := include "common.metadata.annotations" (dict "root" $ "defaults" $orderingAnn "annotations" (dig "annotations" dict $val)) | trim }}
*/}}
{{- define "common.metadata.annotations" -}}
{{- $values := include "common._values" .root | fromYaml | default dict -}}
{{- $syncOptKey := "argocd.argoproj.io/sync-options" -}}
{{- $globalAnn := dig "global" "annotations" dict $values -}}
{{- $ownAnn := default dict .annotations -}}
{{- $defaultsIn := .defaults -}}
{{- $defaultsMap := dict -}}
{{- if kindIs "string" $defaultsIn -}}
  {{- $defaultsMap = fromYaml $defaultsIn | default dict -}}
{{- else if kindIs "map" $defaultsIn -}}
  {{- $defaultsMap = $defaultsIn -}}
{{- end -}}

{{- $syncOpts := list -}}
{{- range $layer := (list $globalAnn $defaultsMap $ownAnn) -}}
  {{- if hasKey $layer $syncOptKey -}}
    {{- range $opt := splitList "," (index $layer $syncOptKey | toString) -}}
      {{- $opt = trim $opt -}}
      {{- if and $opt (not (has $opt $syncOpts)) -}}
        {{- $syncOpts = append $syncOpts $opt -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- /* Precedence (lowest to highest): global.annotations < defaults < the
       resource's own annotations — later layers overwrite earlier ones. */ -}}
{{- $merged := dict -}}
{{- range $layer := (list $globalAnn $defaultsMap $ownAnn) -}}
  {{- range $k, $v := $layer -}}
    {{- if ne $k $syncOptKey -}}
      {{- $_ := set $merged $k ($v | toString) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if gt (len $syncOpts) 0 -}}
  {{- $_ := set $merged $syncOptKey (join "," $syncOpts) -}}
{{- end -}}

{{- /* Emit per key (not one whole-map `toYaml`) so `force-sync` —
       secrets.annotations.default's own already-rendered timestamp, quoted
       there via Sprig `quote` — can be force-quoted explicitly. `toYaml`
       only re-quotes a value when go-yaml's own ambiguity check thinks it
       looks like another scalar type (bool/int/null/timestamp); a Go
       time.Time's default String() text does not trip that check, so a
       naive fromYaml/toYaml round-trip through this helper would silently
       drop its quoting. Every other key (ordering weights, hook fields,
       Prune=false, resource-policy: keep, and any global/own-annotations
       value) keeps rendering through `toYaml`, byte-identical to before
       `defaults` existed, so already-correct callers see no change. */ -}}
{{- range $k := (keys $merged | sortAlpha) }}
{{- if eq $k "force-sync" }}
{{ $k }}: {{ index $merged $k | quote }}
{{- else }}
{{ toYaml (dict $k (index $merged $k)) }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Retention metadata for data-bearing and shared objects.

`helm.sh/resource-policy: keep` is inert under ArgoCD — ArgoCD never runs
helm install/upgrade — so the ArgoCD-native `Prune=false` sync-option is
emitted alongside it. Both are emitted under argocd so the guarantee survives
a later migration back to plain Helm.

Usage: {{- include "common.annotations.retain" $ctx }}
*/}}
{{- define "common.annotations.retain" -}}
helm.sh/resource-policy: keep
{{- if eq (include "common.deployTool" .) "argocd" }}
argocd.argoproj.io/sync-options: Prune=false
{{- end }}
{{- end -}}
