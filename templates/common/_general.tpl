{{/*
=============================================================================
COMMON HELM TEMPLATES
Core library of common Kubernetes template helpers for consistent application deployment.
=============================================================================
*/}}

{{/*
=============================================================================
IDENTITY / NAME RESOLUTION HELPERS
=============================================================================
*/}}

{{/*
Convert `.Values` (chartutil.Values type) into a plain map[string]interface{}
that `dig` understands. This is the single round-trip per helper invocation;
without it `dig` errors with `interface conversion`. Kept private (`_`)
because consumers should never need it.
*/}}
{{- define "common._values" -}}
{{- if hasKey . "Values" -}}
{{- toYaml .Values -}}
{{- else -}}
{{- toYaml dict -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the application name (label `app.kubernetes.io/name`).
Lookup order:
  1. .svc passed via helper context
  2. .Values.global.name
  3. .Values.app.name
  4. .Values.name
  5. .Values.werf.name (legacy fallback)
  6. .Chart.Name
  7. literal "app"

Deliberately does NOT fall back to `.Values.global.werf.name` (the
werf-injected service value): `app.kubernetes.io/name` lands in
`spec.selector.matchLabels` (see `common.labels.matchLabels`), which is
immutable. For a werf chart that does not hand-write `werf.name`, that
fallback would flip the resolved name — and the selector with it — on
upgrade, and `helm upgrade`/`werf converge` would fail with `field is
immutable`. `common.environment` (below) takes the equivalent
`global.werf.env` fallback because `helm.sh/environment` is never a
selector key.
*/}}
{{- define "common.appName" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $chartName := "" -}}
{{- with .Chart }}
  {{- $chartName = .Name -}}
{{- end }}
{{- coalesce .svc (dig "global" "name" nil $values) (dig "app" "name" nil $values) (dig "name" nil $values) (dig "werf" "name" nil $values) $chartName "app" -}}
{{- end }}

{{/*
Resolve the environment label (`helm.sh/environment`).
Lookup order:
  1. .env passed via helper context
  2. .Values.global.environment / .Values.global.env
  3. .Values.environment / .Values.env
  4. .Values.werf.env (legacy fallback)
  5. .Values.global.werf.env (werf-injected)
  6. literal "default"
*/}}
{{- define "common.environment" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- coalesce .env (dig "global" "environment" nil $values) (dig "global" "env" nil $values) (dig "environment" nil $values) (dig "env" nil $values) (dig "werf" "env" nil $values) (dig "global" "werf" "env" nil $values) "default" -}}
{{- end }}

{{/*
DNS-safe component name for resource metadata (`-` separated).
Routes through common.safeName so all metadata.name sanitization
(lowercase, `.`/`_` → `-`, trailing-`-` trim, 63-char truncation) lives
in a single helper.
*/}}
{{- define "common.componentName" -}}
{{- include "common.safeName" (dict "name" (required "Component name is required" .cmp)) | trim -}}
{{- end }}

{{/*
DNS-safe variant of an arbitrary component string.
Usage: {{ include "common.cmp.dns" "my_worker" }}  -> my-worker
*/}}
{{- define "common.cmp.dns" -}}
{{- . | replace "_" "-" -}}
{{- end }}

{{/*
Values-key variant of a component string (`_` separated, matching values yaml keys).
Usage: {{ include "common.cmp.valuesKey" "my-worker" }} -> my_worker
*/}}
{{- define "common.cmp.valuesKey" -}}
{{- . | replace "-" "_" -}}
{{- end }}

{{/*
Release name resolution helper.
*/}}
{{- define "common.releaseName" -}}
{{- if .release -}}
{{ .release }}
{{- else if .Release -}}
{{ .Release.Name }}
{{- end -}}
{{- end }}

{{/*
Build the standard label-context dict shared by every chart helper.
Returned shape (rendered via `fromYaml`):
  svc, cmp, env, version (optional), extraLabels (optional)

NOTE: Values, Release, and Chart are NOT preserved — fromYaml round-trip
drops non-serializable objects. Use common.workload.context.doc (below) for
the live render context assembled inline by each resource template.

Usage:
  {{- $ctx := include "common.labelCtx" . | fromYaml }}
*/}}
{{- define "common.labelCtx" -}}
svc: {{ include "common.appName" . | trim | quote }}
cmp: {{ include "common.componentName" . | trim | quote }}
env: {{ include "common.environment" . | trim | quote }}
{{- $instance := include "common.releaseName" . | trim }}
{{- if $instance }}
release: {{ $instance | quote }}
{{- end }}
{{- with .version }}
version: {{ . | quote }}
{{- end }}
{{- with .extraLabels }}
extraLabels: {{ toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Canonical label/render context shape consumed DIRECTLY (not via fromYaml) by
every resource template:
  svc, cmp, env, Values, Release, Chart   (+ optional version, extraLabels)

Helm `include` can only return a string, so the live Values/Release/Chart
objects cannot be produced by a builder helper — each resource template
assembles the dict literal inline:

  {{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

This define is the single documented source of that shape. NOTE: common.labelCtx
(above) round-trips through fromYaml and therefore DROPS Values/Release/Chart;
it is retained only for the legacy scalar-only callers and must NOT be used to
build a render context.
*/}}
{{- define "common.workload.context.doc" -}}
svc, cmp, env, Values, Release, Chart
{{- end -}}

{{/*
=============================================================================
LABEL HELPERS
=============================================================================
*/}}

{{/*
Common labels applied to every resource.
Usage: {{ include "common.labels" (dict "svc" "my-service" "cmp" "web" "env" "prod" "Values" .Values) }}
*/}}
{{- define "common.labels" -}}
{{- $svc := include "common.appName" . | trim -}}
{{- $cmp := default "" .cmp -}}
{{- $env := include "common.environment" . | trim -}}
{{- $instance := include "common.releaseName" . | trim -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $emitEnv := dig "global" "emitEnvironmentLabel" true $values -}}
{{- with .Chart -}}
helm.sh/chart: {{ printf "%s-%s" .Name (.Version | replace "+" "_") }}
{{- end }}
app.kubernetes.io/name: {{ $svc }}
{{- if $cmp }}
app.kubernetes.io/component: {{ $cmp }}
{{- end }}
{{- if and $env $emitEnv }}
helm.sh/environment: {{ $env }}
{{- end }}
{{- if $instance }}
app.kubernetes.io/instance: {{ $instance }}
{{- end }}
{{- /* Under ArgoCD there is no Helm release behind the manifest — no release
       Secret, no `helm history`, no `helm rollback` — so claiming Helm here
       misleads operators and cleanup tooling. */}}
app.kubernetes.io/managed-by: {{ ternary "argocd" (.Release.Service | default "Helm") (eq (include "common.deployTool" .) "argocd") }}
{{- /* .Chart may be a struct (helm 3 / werf render context) or a map
     (helm 4, or a caller-built dict). `dig` only traverses maps, so use
     field access via `with`, which works on both. */ -}}
{{- $version := default "" .version }}
{{- if not $version }}
{{- with .Chart }}{{- $version = .AppVersion }}{{- end }}
{{- end }}
{{- with $version }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with dig "global" "selectorLabels" dict $values }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- /* Chart-wide labels merge first; a caller-supplied extraLabels wins. */ -}}
{{- $extra := dig "global" "extraLabels" dict $values }}
{{- with .extraLabels }}{{- $extra = mergeOverwrite (deepCopy $extra) . }}{{- end }}
{{- with $extra }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}

{{/*
Stable match-labels for selectors. Selectors are immutable on existing
Deployments / StatefulSets, so this set is the minimum stable identity.

By default, emits: name, component, environment, instance.

Set `.Values.global.compat.legacySelectorLabels: true` to additionally include
`version` and any `extraLabels` in selectors -- useful only when migrating
from a chart whose pre-1.3 release stored those labels in the selector.

Usage: {{ include "common.labels.matchLabels" (dict "svc" "my-service" "cmp" "web" "env" "prod" "Values" .Values) }}
*/}}
{{- define "common.labels.matchLabels" -}}
{{- $svc := include "common.appName" . | trim -}}
{{- $cmp := default "" .cmp -}}
{{- $instance := include "common.releaseName" . | trim -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $legacy := dig "global" "compat" "legacySelectorLabels" false $values -}}
app.kubernetes.io/name: {{ $svc }}
{{- if $cmp }}
app.kubernetes.io/component: {{ $cmp }}
{{- end }}
{{- /* ArgoCD rewrites app.kubernetes.io/instance in metadata and pod-template
       labels but never in spec.selector, so when the ArgoCD instance name and
       the Helm release name diverge the selector stops matching. Opting out is
       NEW-INSTALL ONLY: selectors are immutable, and removing this key from a
       live workload requires delete/recreate. Supply global.selectorLabels as
       a replacement discriminator when you do. */ -}}
{{- $instanceInSelector := dig "global" "compat" "instanceInSelector" true $values }}
{{- if and $instance $instanceInSelector }}
app.kubernetes.io/instance: {{ $instance }}
{{- end }}
{{- with dig "global" "selectorLabels" dict $values }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- if $legacy }}
{{- with .version }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with .extraLabels }}
{{ toYaml . | nindent 0 }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
=============================================================================
ANNOTATION HELPERS
=============================================================================
*/}}

{{/*
DEPRECATED — use `common.deployTool` directly. Retained for one minor so
consumer charts calling it keep working. Returns "true" when the active
dialect is werf.
*/}}
{{- define "common.werf.annotationsEnabled" -}}
{{- ternary "true" "false" (eq (include "common.deployTool" .) "werf") -}}
{{- end }}

{{/*
DEPRECATED — alias of `common.annotations.lifecycle`.
*/}}
{{- define "common.annotations.werf" -}}
{{- include "common.annotations.lifecycle" . -}}
{{- end -}}

{{/*
Process annotations from a dictionary that has an `annotations` sub-key.

Returns ONLY the YAML body of the annotations map (no leading `annotations:` key).
The caller is responsible for emitting the `annotations:` line itself, gated on
the helper output being non-empty. This avoids doubled `annotations:` blocks
when a caller (which also needs to indent the output) wraps the include site.

Usage:
  {{- $ann := include "common.annotations" $myConfig | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 4 }}
  {{- end }}
*/}}
{{- define "common.annotations" -}}
{{- if kindIs "map" . -}}
{{- if hasKey . "annotations" -}}
{{- with .annotations }}
{{- $coerced := dict }}
{{- range $k, $v := . }}{{- $_ := set $coerced $k ($v | toString) }}{{- end }}
{{- toYaml $coerced }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
=============================================================================
TEMPLATE UTILITY HELPERS
=============================================================================
*/}}

{{/*
Safely render a template with a default value.
Usage: {{ include "common.renderTemplateOrDefault" (dict "name" "my-template" "context" $ "default" "default-value") }}
*/}}
{{- define "common.renderTemplateOrDefault" }}
{{- $result := include .name .context | trim }}
{{- if $result }}
{{ $result }}
{{- else }}
{{ .default }}
{{- end }}
{{- end }}

{{/*
Generate a random string with a prefix and optional separator.
Usage: {{ include "common.generateName" (dict "prefix" "app" "separator" "-" "length" 8) }}
*/}}
{{- define "common.generateName" }}
{{- include "common.argocd.requireCluster" (dict "root" (default dict .root) "helper" "common.generateName" "detail" "use the deterministic `generateName` helper in _helpers.tpl with a content-derived suffix (an image tag, digest, or the sha256 from common.configChecksum)") -}}
{{- $prefix := default "" .prefix }}
{{- $separator := default "-" .separator }}
{{- $length := default 8 .length }}
{{- if $prefix }}
{{ printf "%s%s%s" $prefix $separator (randAlphaNum $length | lower) }}
{{- else }}
{{ randAlphaNum $length | lower }}
{{- end }}
{{- end }}

{{/*
Format a value based on its type.
Usage: {{ include "common.format" (dict "value" .Values.someValue "type" "json") }}
*/}}
{{- define "common.format" }}
{{- $value := .value }}
{{- $type := default "yaml" .type }}
{{- if eq $type "json" }}
{{ $value | toJson }}
{{- else if eq $type "raw" }}
{{ $value }}
{{- else }}
{{ $value | toYaml }}
{{- end }}
{{- end }}

{{/*
Merge two maps via Sprig `merge $dest $src` (dest-wins): keys already
present in `dest` are kept; `src` only fills absent keys. NOT a deep
override merge — see docs/values-reference.md#public-helpers.
Usage: {{ include "common.mergeValues" (dict "src" $srcMap "dest" $destMap) }}
*/}}
{{- define "common.mergeValues" }}
{{- $src := .src }}
{{- $dest := .dest }}
{{/* deepCopy $dest so Sprig `merge` (which mutates its first arg) does not
     write $src's keys back into the caller's map — matches every other merge
     in the tree and honors the chart's immutability contract. */}}
{{ toYaml (merge (deepCopy $dest) $src) }}
{{- end }}

{{/*
=============================================================================
SPECIALIZED HELPERS
=============================================================================
*/}}

{{/*
Format a URL with protocol, host and optional path.
Defaults `protocol` to `https`. Pass `protocol: "http"` explicitly to opt
into insecure transport.
Usage: {{ include "common.formatUrl" (dict "protocol" "https" "host" "example.com" "path" "/api/v1") }}
*/}}
{{- define "common.formatUrl" }}
{{- $protocol := default "https" .protocol }}
{{- $host := .host }}
{{- $path := default "" .path }}
{{- if and $host $protocol }}
{{ printf "%s://%s%s" $protocol $host $path }}
{{- else }}
{{ fail "Host is required for URL formatting" }}
{{- end }}
{{- end }}

{{/*
Format a database URL from components.

NOTE: `user` and `password` are interpolated verbatim. They are NOT
URL-encoded. Callers passing values that may contain `@`, `:`, `/`, `?`,
`#`, or other URL-reserved characters MUST pre-encode them (e.g. wrap
with `urlquery`) or the resulting connection string will be invalid.

Usage: {{ include "common.dbUrl" (dict "type" "postgres" "host" "db.example.com" "port" "5432" "name" "mydb" "user" "dbuser" "password" "secret") }}
*/}}
{{- define "common.dbUrl" }}
{{- $type := default "postgres" .type }}
{{- $host := .host }}
{{- $port := .port }}
{{- $name := .name }}
{{- $user := .user }}
{{- $password := .password }}
{{- $options := default "" .options }}
{{- if and $host $name }}
{{- /* Build the host[:port] authority. Coerce the port with `toString` so an
       integer port (the natural YAML form) doesn't render as `%!s(int=5432)`,
       and omit the `:port` segment entirely when no port is supplied. */ -}}
{{- $authority := $host }}
{{- if $port }}{{- $authority = printf "%s:%s" $host ($port | toString) }}{{- end }}
{{- if and $user $password }}
{{ printf "%s://%s:%s@%s/%s%s" $type $user $password $authority $name $options }}
{{- else }}
{{ printf "%s://%s/%s%s" $type $authority $name $options }}
{{- end }}
{{- else }}
{{ fail "Host and database name are required for DB URL formatting" }}
{{- end }}
{{- end }}

{{/*
Generate a DNS-safe name.
Usage: {{ include "common.safeName" (dict "name" "my.service-name_here" "maxLength" 63) }}
*/}}
{{- define "common.safeName" }}
{{- $name := regexReplaceAll "-+$" (.name | lower | replace "." "-" | replace "_" "-" | trunc (default 63 .maxLength)) "" }}
{{ $name }}
{{- end }}

{{/*
Indent multiline strings with a specified number of spaces.
Usage: {{ include "common.indent" (dict "value" $multilineString "spaces" 2) }}
*/}}
{{- define "common.indent" -}}
{{- $lines := splitList "\n" .value -}}
{{- $indent := repeat (default 2 .spaces | int) " " -}}
{{- range $i, $line := $lines -}}
{{- if $i }}
{{ $indent }}{{ $line }}
{{- else -}}
{{ $line }}
{{- end -}}
{{- end -}}
{{- end -}}
