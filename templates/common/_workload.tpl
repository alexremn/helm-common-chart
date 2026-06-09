{{/*
=============================================================================
WORKLOAD POD SPEC HELPERS
Shared helpers to render pod specs consistently across workload types.
=============================================================================
*/}}

{{/*
Render a string from a string-or-map image specification.

Supported map shapes:
  { image: "registry/repo:tag" }                     # pre-formatted, used as-is
  { repository: "repo", tag: "1.0" }                 # repo:tag
  { repository: "repo", digest: "sha256:..." }       # repo@sha256:...
  { registry: "ghcr.io", repository: "repo", tag: "1.0" }   # registry/repo:tag
  { name: "...", tag: "..." }                        # alias of `repository`
  { repository: "repo" }                             # repo:<Chart.appVersion>

Usage: {{ include "common.image.toString" $imgValue }}
*/}}
{{- define "common.image.toString" -}}
{{- if kindIs "string" . -}}
{{ . }}
{{- else if kindIs "map" . -}}
  {{- if hasKey . "image" -}}
    {{- if not (kindIs "string" .image) -}}
      {{- fail (printf "Image map field 'image' must be a pre-formatted string (e.g. 'registry/repo:tag'). Got %s. Use 'repository'+'tag' (or 'digest') instead." (kindOf .image)) -}}
    {{- end -}}
{{ .image }}
  {{- else -}}
    {{- $repository := coalesce .repository .name -}}
    {{- if not $repository -}}
      {{- fail "Image map must include either 'image' or 'repository'." -}}
    {{- end -}}
    {{- $registry := default "" .registry -}}
    {{- $base := $repository -}}
    {{- if $registry -}}
      {{- $base = printf "%s/%s" (trimSuffix "/" $registry) $repository -}}
    {{- end -}}
    {{- if .digest -}}
{{ printf "%s@%s" $base .digest }}
    {{- else if .tag -}}
{{ printf "%s:%s" $base (.tag | toString) }}
    {{- else if .version -}}
{{ printf "%s:%s" $base (.version | toString) }}
    {{- else -}}
{{- fail (printf "Image %q has no tag, digest, or version, and .Chart.AppVersion is empty. Refusing to render an untagged image." $base) -}}
    {{- end -}}
  {{- end -}}
{{- else -}}
{{- fail "Unsupported image format. Use string or map." -}}
{{- end -}}
{{- end }}

{{/*
Render workload-level annotations (werf + user annotations + optional
extra key/value), or emit nothing when no source is present.

Used by Deployment and StatefulSet renderers (and any future workload
kind that follows the same contract).

Parameters:
  root      — chart root (passed to common.annotations.werf)
  component — component values map (.annotations is honored)
  extra     — optional dict of additional `key: value` annotations to
              merge on top (e.g. `werf.io/replicas-on-creation`)

Emits the full `annotations:` block at the current indent + 2 spaces
(matches the existing call sites at workload metadata level).

Usage:
  {{- $extra := dict }}
  {{- if $shouldEmitReplicasAnn }}{{- $_ := set $extra "werf.io/replicas-on-creation" ($componentValues.scaling.min | toString) }}{{- end }}
  {{- include "common.workload.annotations" (dict "root" $ "component" $componentValues "extra" $extra) | nindent 2 }}
*/}}
{{- define "common.workload.annotations" -}}
{{- $root := default dict .root -}}
{{- $component := default dict .component -}}
{{- $extra := default dict .extra -}}
{{- $werfAnn := include "common.annotations.werf" $root | trim -}}
{{- $userAnn := dig "annotations" dict $component -}}
{{- if or $werfAnn (gt (len $userAnn) 0) (gt (len $extra) 0) }}
  annotations:
    {{- if $werfAnn }}
    {{- $werfAnn | nindent 4 }}
    {{- end }}
    {{- with $userAnn }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- range $key, $val := $extra }}
    {{ $key }}: {{ $val | quote }}
    {{- end }}
{{- end -}}
{{- end -}}

{{/*
Resolve the container image for a workload component.
Lookup order:
  1. component.image (string or map)
  2. .Values.global.image
  3. .Values.werf.image.app  (legacy)
  4. .Chart.AppVersion, as the tag for repository-only image maps
*/}}
{{- define "common.workload.image" -}}
{{- $root := .root -}}
{{- $component := default dict .component -}}
{{- $cmp := default "" .cmp -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $candidate := coalesce $component.image (dig "global" "image" nil $values) (dig "werf" "image" "app" nil $values) -}}
{{- if empty $candidate -}}
  {{- fail (printf "Unable to resolve image for component '%s'. Tried (in order): component.image, .Values.global.image, .Values.werf.image.app." $cmp) -}}
{{- end -}}
{{- if and (kindIs "map" $candidate) (not (or (hasKey $candidate "image") (hasKey $candidate "tag") (hasKey $candidate "version") (hasKey $candidate "digest"))) (default "" $root.Chart.AppVersion) -}}
  {{- $candidate = set (deepCopy $candidate) "tag" $root.Chart.AppVersion -}}
{{- end -}}
{{ include "common.image.toString" $candidate }}
{{- end }}

{{/*
Resolve `imagePullPolicy`. See `docs/values-reference.md` for resolution order.
*/}}
{{- define "common.workload.imagePullPolicy" -}}
{{- $root := .root -}}
{{- $component := default dict .component -}}
{{- $image := default "" .image -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $componentImagePullPolicy := "" -}}
{{- if and (kindIs "map" $component) (hasKey $component "image") (kindIs "map" $component.image) -}}
  {{- $componentImagePullPolicy = $component.image.pullPolicy -}}
{{- end -}}
{{- /* Default pull policy is IfNotPresent, but switch to Always when the
     resolved image string ends with ":latest" to avoid stale-cache skew
     across nodes. Explicit override (component.imagePullPolicy or global)
     always wins regardless of tag. The resolved image string is passed in
     by the caller (see render-pod-spec) so we don't re-invoke
     common.workload.image just to peek at the tag. */ -}}
{{- $defaultPolicy := "IfNotPresent" -}}
{{- if hasSuffix ":latest" (trim $image) -}}
  {{- $defaultPolicy = "Always" -}}
{{- end -}}
{{- $policy := coalesce $component.imagePullPolicy $componentImagePullPolicy (dig "global" "imagePullPolicy" nil $values) (dig "global" "image" "pullPolicy" nil $values) (dig "werf" "image" "pullPolicy" nil $values) $defaultPolicy -}}
{{ $policy }}
{{- end }}

{{/*
Render a full pod spec body for a workload.

Toggle flags — all default to false when omitted. For a "full" workload
(Deployment, StatefulSet, DaemonSet) pass all flags as true. Job and
CronJob intentionally omit probes, lifecycle, and termination-grace to
match Kubernetes semantics for short-lived pods.

  includePorts                  — emit container ports block
  includeProbes                 — emit liveness/readiness/startup probes
  includeLifecycle              — emit lifecycle hook block
  includePriorityClassName      — emit priorityClassName
  includeHostAliases            — emit hostAliases
  includeTopologySpreadConstraints — emit topologySpreadConstraints
  includeTerminationGracePeriod — emit terminationGracePeriodSeconds

Canonical "full" toggle set (Deployment / StatefulSet / DaemonSet):
  includePorts: true
  includeProbes: true
  includeLifecycle: true
  includePriorityClassName: true
  includeHostAliases: true
  includeTopologySpreadConstraints: true
  includeTerminationGracePeriod: true

NOTE: Defaulting all toggles to false means a new workload kind that
forgets a flag will silently emit pods without that section. Long-lived
workloads avoid this by using the `common.workload.fullToggles` preset
(single source of the 7-flag "full" set); Job/CronJob still opt in to the
subset they need. Inverting the underlying defaults to true is deferred
because it would flip golden output for Job/CronJob variants.

Usage:
{{ include "common.workload.podSpec" (dict
  "root" $
  "component" $componentValues
  "svc" $svc
  "cmp" $cmp
  "env" $env
  "includePorts" true
  "includeProbes" true
  "includeLifecycle" true
  "includePriorityClassName" true
  "includeHostAliases" true
  "includeTopologySpreadConstraints" true
  "includeTerminationGracePeriod" true
) }}
*/}}
{{/*
Canonical "full" pod-spec toggle set for long-lived workloads
(Deployment / StatefulSet / DaemonSet). Centralizes the 7 include* flags
so they aren't triplicated at each call site. Returns YAML to be merged
into the podSpec args via `fromYaml`.

Usage:
  {{- include "common.workload.podSpec" (merge (dict
      "root" $ "component" $componentValues "svc" $svc "cmp" $cmp "env" $env)
      (include "common.workload.fullToggles" . | fromYaml)) | nindent 6 }}
*/}}
{{- define "common.workload.fullToggles" -}}
includePorts: true
includeProbes: true
includeLifecycle: true
includePriorityClassName: true
includeHostAliases: true
includeTopologySpreadConstraints: true
includeTerminationGracePeriod: true
{{- end -}}
{{- define "common.workload.podSpec" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $svc := .svc -}}
{{- $cmp := .cmp -}}
{{- $env := .env -}}
{{- $includePorts := default false .includePorts -}}
{{- $includeProbes := default false .includeProbes -}}
{{- $includeLifecycle := default false .includeLifecycle -}}
{{- $includePriorityClassName := default false .includePriorityClassName -}}
{{- $includeHostAliases := default false .includeHostAliases -}}
{{- $includeTopologySpreadConstraints := default false .includeTopologySpreadConstraints -}}
{{- $includeTerminationGracePeriod := default false .includeTerminationGracePeriod -}}
{{- if $includePriorityClassName -}}
  {{- $pc := include "common.priorityClassName" $component | trim -}}
  {{- if $pc -}}
{{ $pc }}
{{ end -}}
{{- end -}}
{{- if $includeHostAliases -}}
  {{- $ha := include "common.hostAliases" $component | trim -}}
  {{- if $ha -}}
{{ $ha }}
{{ end -}}
{{- end -}}
{{- /* F10: resolve image string ONCE; share with imagePullPolicy so the
       :latest-suffix check doesn't re-invoke common.workload.image. */ -}}
{{- $imageStr := include "common.workload.image" (dict "root" $root "component" $component "cmp" $cmp) -}}
containers:
  - name: {{ $cmp }}
    image: {{ $imageStr }}
    imagePullPolicy: {{ include "common.workload.imagePullPolicy" (dict "root" $root "component" $component "image" $imageStr) | quote }}
    {{- $cmd := include "common.command" $component | trim }}
    {{- if $cmd }}
    {{- $cmd | nindent 4 }}
    {{- end }}
    {{- $args := include "common.args" $component | trim }}
    {{- if $args }}
    {{- $args | nindent 4 }}
    {{- end }}
    {{- if $includePorts }}
    {{- $ports := include "common.ports" $component | trim }}
    {{- if $ports }}
    {{- $ports | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- $envFrom := include "common.envFrom" (dict "svc" $component "global" (default dict $root.Values.global) "root" $root) | trim }}
    {{- if $envFrom }}
    {{- $envFrom | nindent 4 }}
    {{- end }}
    {{- /* F2: pass a curated context (Values/Release/Chart + componentValues)
           so consumer env templates can read root .Values without exposing
           the full chart root (sibling components, helm built-ins). */ -}}
    {{- $envs := include "common.envs" (dict "Values" $root.Values "Release" $root.Release "Chart" $root.Chart "componentValues" $component) | trim }}
    {{- if $envs }}
    {{- $envs | nindent 4 }}
    {{- end }}
    {{- $res := include "common.resources" $component | trim }}
    {{- if $res }}
    {{- $res | nindent 4 }}
    {{- end }}
    {{- if $includeProbes }}
    {{- $probes := include "common.probes" (merge (deepCopy $component) (dict "_root" $root)) | trim }}
    {{- if $probes }}
    {{- $probes | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- $secCtx := include "common.container.securityContext" (dict "root" $root "component" $component) | trim }}
    {{- if $secCtx }}
    {{- $secCtx | nindent 4 }}
    {{- end }}
    {{- if $includeLifecycle }}
    {{- $lc := include "common.lifecycle" $component | trim }}
    {{- if $lc }}
    {{- $lc | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- $vm := include "common.volumeMounts" $component | trim }}
    {{- if $vm }}
    {{- $vm | nindent 4 }}
    {{- end }}
    {{- with $component.extraContainerConfig }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- $ic := include "common.initContainers" $component | trim }}
{{- if $ic }}
{{ $ic }}
{{- end }}
{{- with .restartPolicy }}
restartPolicy: {{ . | quote }}
{{- end }}
{{- if $includeTerminationGracePeriod }}
terminationGracePeriodSeconds: {{ default 30 $component.terminationGracePeriod }}
{{- end }}
{{- /* Table-driven emission of pod-spec sections. Each entry is the
       already-rendered & trimmed section body; empty entries are skipped.
       Order is significant — it dictates the YAML field order in the
       rendered pod spec. */ -}}
{{- $sections := list
    (include "common.pod.securityContext" (dict "root" $root "component" $component) | trim)
    (include "common.tolerations" (dict "component" $component "root" $root) | trim)
    (include "common.affinity" (dict "val" $component "svc" $svc "cmp" $cmp "env" $env) | trim)
    (include "common.serviceAccount" (dict "component" $component "root" $root "cmp" $cmp) | trim)
    (include "common.volumes" $component | trim)
    (include "common.nodeSelector" $component | trim)
    (include "common.imagePullSecrets" (dict "component" $component "root" $root) | trim)
-}}
{{- if $includeTopologySpreadConstraints -}}
  {{- $sections = append $sections (include "common.topologySpreadConstraints" $component | trim) -}}
{{- end -}}
{{- $sections = append $sections (include "common.podRuntime" $component | trim) -}}
{{- range $section := $sections }}
{{- if $section }}
{{ $section }}
{{- end }}
{{- end }}
{{- with $component.extraPodConfig }}
{{ toYaml . }}
{{- end }}
{{- end -}}
