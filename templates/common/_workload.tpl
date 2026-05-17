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
Resolve `imagePullPolicy`. See `docs/values-contract.md` for resolution order.
*/}}
{{- define "common.workload.imagePullPolicy" -}}
{{- $root := .root -}}
{{- $component := default dict .component -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $componentImagePullPolicy := "" -}}
{{- if and (kindIs "map" $component) (hasKey $component "image") (kindIs "map" $component.image) -}}
  {{- $componentImagePullPolicy = $component.image.pullPolicy -}}
{{- end -}}
{{- $policy := coalesce $component.imagePullPolicy $componentImagePullPolicy (dig "global" "imagePullPolicy" nil $values) (dig "global" "image" "pullPolicy" nil $values) (dig "werf" "image" "pullPolicy" nil $values) "IfNotPresent" -}}
{{ $policy }}
{{- end }}

{{/*
Render a full pod spec body for a workload.
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
containers:
  - name: {{ $cmp }}
    image: {{ include "common.workload.image" (dict "root" $root "component" $component "cmp" $cmp) }}
    imagePullPolicy: {{ include "common.workload.imagePullPolicy" (dict "root" $root "component" $component) | quote }}
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
    {{- $envs := include "common.envs" $component | trim }}
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
{{- $podSec := include "common.pod.securityContext" (dict "root" $root "component" $component) | trim }}
{{- if $podSec }}
{{ $podSec }}
{{- end }}
{{- $tol := include "common.tolerations" (dict "component" $component "root" $root) | trim }}
{{- if $tol }}
{{ $tol }}
{{- end }}
{{- $aff := include "common.affinity" (dict "val" $component "svc" $svc "cmp" $cmp "env" $env) | trim }}
{{- if $aff }}
{{ $aff }}
{{- end }}
{{- $sa := include "common.serviceAccount" (dict "component" $component "root" $root "cmp" $cmp) | trim }}
{{- if $sa }}
{{ $sa }}
{{- end }}
{{- $vol := include "common.volumes" $component | trim }}
{{- if $vol }}
{{ $vol }}
{{- end }}
{{- $ns := include "common.nodeSelector" $component | trim }}
{{- if $ns }}
{{ $ns }}
{{- end }}
{{- $ips := include "common.imagePullSecrets" (dict "component" $component "root" $root) | trim }}
{{- if $ips }}
{{ $ips }}
{{- end }}
{{- if $includeTopologySpreadConstraints }}
{{- $tsc := include "common.topologySpreadConstraints" $component | trim }}
{{- if $tsc }}
{{ $tsc }}
{{- end }}
{{- end }}
{{- $pr := include "common.podRuntime" $component | trim }}
{{- if $pr }}
{{ $pr }}
{{- end }}
{{- with $component.extraPodConfig }}
{{ toYaml . }}
{{- end }}
{{- end -}}
