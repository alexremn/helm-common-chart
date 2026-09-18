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
Selector labels for a component: `global.selectorLabels` merged with the
component's own `<cmp>.selectorLabels`, the component winning on a clash.

Unlike `global.extraLabels` these land in BOTH `common.labels` and every
generated selector, and unlike `global.selectorLabels` alone they can differ
per component -- which is what lets one chart reproduce a pre-existing
`app.kubernetes.io/part-of` grouping, or give a component an
`app.kubernetes.io/component` label that differs from its component key (a
Deployment named `web-general` selecting on `part-of: web, component: general`).

Selectors are IMMUTABLE. These keys are therefore new-install-only on a live
workload, exactly like `global.selectorLabels`; the supported use is
reproducing an existing selector during a chart migration, not changing one.

The component's own map is looked up in the three places a component can be
declared, first hit wins:
  .Values.<key>                 workloads (Deployment/StatefulSet/DaemonSet/...)
  .Values.cronjobs.<key>
  .Values.jobs.<key>
where <key> is the component name with dashes swapped for underscores
(`common.cmp.valuesKey`). Each step is guarded on the node actually being a
map, so a component name that collides with an unrelated scalar or list value
resolves to "no labels" instead of failing the render.

Usage: {{ include "common.selectorLabels" $labelCtx | fromYaml }}
*/}}
{{- define "common.selectorLabels" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $out := dig "global" "selectorLabels" dict $values -}}
{{- $cmp := default "" .cmp -}}
{{- if $cmp -}}
  {{- $key := include "common.cmp.valuesKey" $cmp -}}
  {{- $own := dict -}}
  {{- range $holder := (list $values (index $values "cronjobs") (index $values "jobs")) -}}
    {{- if and (not $own) (kindIs "map" $holder) -}}
      {{- $node := index $holder $key -}}
      {{- if kindIs "map" $node -}}
        {{- $candidate := index $node "selectorLabels" -}}
        {{- if kindIs "map" $candidate }}{{- $own = $candidate }}{{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if $own }}{{- $out = mergeOverwrite (deepCopy $out) $own }}{{- end -}}
{{- end -}}
{{- toYaml (default dict $out) -}}
{{- end -}}

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
{{- /* .Chart may be a struct (helm 3 / werf render context) or a map
       (helm 4, or a caller-built dict). `dig` only traverses maps, so use
       field access via `with`, which works on both. */ -}}
{{- $version := default "" .version -}}
{{- if not $version }}{{- with .Chart }}{{- $version = .AppVersion }}{{- end }}{{- end -}}

{{- /* Chart-wide labels merge first; a caller-supplied extraLabels wins.
       Both also OVERRIDE a chart-emitted label of the same key.

       They used to be appended as a SECOND YAML block after the chart's own
       labels, so overriding one — pinning app.kubernetes.io/managed-by back to
       Helm under `deployTool: argocd`, say — emitted the key twice and every
       strict decoder rejected the whole manifest
       (`key "app.kubernetes.io/managed-by" already set in map`), which left no
       way to override a chart label at all. This is the same
       duplicate-mapping-key defect 2.5.0 fixed for annotations, where
       common.metadata.annotations merges its three layers into one map.

       Values coming from extraLabels are quoted: a Kubernetes label value must
       be a string, and an unquoted numeric one (`team: 2024`) is rejected at
       apply time — the same trap `helm.sh/environment` was quoted for. */ -}}
{{- $extra := dig "global" "extraLabels" dict $values -}}
{{- with .extraLabels }}{{- $extra = mergeOverwrite (deepCopy $extra) . }}{{- end -}}
{{- /* Selector labels ride the same override path. They MUST win over
       extraLabels: they are also written into spec.selector, and a selector
       that disagrees with the pod-template labels it is supposed to match
       produces a Deployment that can never find its own pods. */ -}}
{{- $sel := include "common.selectorLabels" . | fromYaml | default dict -}}
{{- if $sel }}{{- $extra = mergeOverwrite (deepCopy $extra) $sel }}{{- end -}}

{{- /* Chart-emitted labels, built as ordered pairs rather than a map: a map
       would render through toYaml in alphabetical order and churn the
       committed render of every consumer in the fleet. */ -}}
{{- $pairs := list -}}
{{- with .Chart }}{{- $pairs = append $pairs (list "helm.sh/chart" (printf "%s-%s" .Name (.Version | replace "+" "_"))) }}{{- end -}}
{{- $pairs = append $pairs (list "app.kubernetes.io/name" $svc) -}}
{{- if $cmp }}{{- $pairs = append $pairs (list "app.kubernetes.io/component" $cmp) }}{{- end -}}
{{- if and $env $emitEnv }}{{- $pairs = append $pairs (list "helm.sh/environment" ($env | quote)) }}{{- end -}}
{{- if $instance }}{{- $pairs = append $pairs (list "app.kubernetes.io/instance" $instance) }}{{- end -}}
{{- /* Under ArgoCD there is no Helm release behind the manifest — no release
       Secret, no `helm history`, no `helm rollback` — so claiming Helm here
       misleads operators and cleanup tooling. Consumers who need the label
       stable across a mixed werf/ArgoCD fleet override it via extraLabels. */ -}}
{{- $pairs = append $pairs (list "app.kubernetes.io/managed-by" (ternary "argocd" (.Release.Service | default "Helm") (eq (include "common.deployTool" .) "argocd"))) -}}
{{- with $version }}{{- $pairs = append $pairs (list "app.kubernetes.io/version" (. | quote)) }}{{- end -}}

{{- $lines := list -}}
{{- $claimed := list -}}
{{- range $p := $pairs -}}
  {{- $k := index $p 0 -}}
  {{- $claimed = append $claimed $k -}}
  {{- if hasKey $extra $k -}}
    {{- $lines = append $lines (printf "%s: %s" $k (index $extra $k | toString | quote)) -}}
  {{- else -}}
    {{- $lines = append $lines (printf "%s: %s" $k (index $p 1)) -}}
  {{- end -}}
{{- end -}}
{{- range $k, $v := $extra -}}
  {{- if not (has $k $claimed) -}}
    {{- $lines = append $lines (printf "%s: %s" $k ($v | toString | quote)) -}}
  {{- end -}}
{{- end -}}
{{ join "\n" $lines }}
{{- end -}}

{{/*
Stable match-labels for selectors. Selectors are immutable on existing
Deployments / StatefulSets, so this set is the minimum stable identity.

By default, emits: name, component, instance. Does NOT include environment --
`helm.sh/environment` is metadata-only (see `common.labels`), never a
selector key.

DEPRECATED: `.Values.global.compat.legacySelectorLabels: true` is scheduled
for removal in 3.0. It is a NO-OP for every chart-generated selector -- none
of the chart's own `$labelCtx` builders populate `version` or `extraLabels`,
so the `with` guards below never fire for chart.* templates. It can only
affect a consumer template that calls this helper (or
`common.affinities.pods.*`) directly with `version`/`extraLabels` in its own
context, including indirectly via `common.labelCtx`, which propagates both
keys. Use `global.selectorLabels` instead -- it is the supported mechanism
for adding a stable discriminator to selectors, and it actually works.

Usage: {{ include "common.labels.matchLabels" (dict "svc" "my-service" "cmp" "web" "env" "prod" "Values" .Values) }}
*/}}
{{- define "common.labels.matchLabels" -}}
{{- $svc := include "common.appName" . | trim -}}
{{- $cmp := default "" .cmp -}}
{{- $instance := include "common.releaseName" . | trim -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $legacy := dig "global" "compat" "legacySelectorLabels" false $values -}}
{{- $sel := include "common.selectorLabels" . | fromYaml | default dict -}}

{{- /* Built as ordered pairs, then overridden in place by $sel, for the same
       reason common.labels does it: appending selector labels as a second
       block emitted `app.kubernetes.io/component` TWICE whenever a consumer
       supplied that key, and a duplicate mapping key makes every strict
       decoder reject the manifest. Overriding in place is also what makes a
       component-specific component label possible at all. */ -}}
{{- $pairs := list (list "app.kubernetes.io/name" $svc) -}}
{{- if $cmp }}{{- $pairs = append $pairs (list "app.kubernetes.io/component" $cmp) }}{{- end -}}
{{- /* ArgoCD rewrites app.kubernetes.io/instance in metadata and pod-template
       labels but never in spec.selector, so when the ArgoCD instance name and
       the Helm release name diverge the selector stops matching. Opting out is
       NEW-INSTALL ONLY: selectors are immutable, and removing this key from a
       live workload requires delete/recreate. Supply global.selectorLabels or
       <cmp>.selectorLabels as a replacement discriminator when you do. */ -}}
{{- $instanceInSelector := dig "global" "compat" "instanceInSelector" true $values -}}
{{- if and $instance $instanceInSelector }}{{- $pairs = append $pairs (list "app.kubernetes.io/instance" $instance) }}{{- end -}}
{{- if $legacy -}}
{{- with .version }}{{- $pairs = append $pairs (list "app.kubernetes.io/version" (. | quote)) }}{{- end -}}
{{- range $k, $v := (default dict .extraLabels) }}{{- $pairs = append $pairs (list $k $v) }}{{- end -}}
{{- end -}}

{{- $lines := list -}}
{{- $claimed := list -}}
{{- range $p := $pairs -}}
  {{- $k := index $p 0 -}}
  {{- if not (has $k $claimed) -}}
    {{- $claimed = append $claimed $k -}}
    {{- if hasKey $sel $k -}}
      {{- $lines = append $lines (printf "%s: %s" $k (index $sel $k | toString | quote)) -}}
    {{- else -}}
      {{- $lines = append $lines (printf "%s: %s" $k (index $p 1)) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range $k, $v := $sel -}}
  {{- if not (has $k $claimed) -}}
    {{- $lines = append $lines (printf "%s: %s" $k ($v | toString | quote)) -}}
  {{- end -}}
{{- end -}}
{{ join "\n" $lines }}
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
Usage: {{ include "common.generateName" (dict "root" $ "prefix" "app" "separator" "-" "length" 8) }}
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
Database connection pool size for a worker-per-core process model.

  workers × threads + extra          when `threads` is given
  workers + extra                    otherwise

`workers` is either passed directly or derived from `cpu`: a Kubernetes CPU
quantity in millicores ("500m" → 1 worker, rounded up) or whole cores ("2").
`extra` (default 5) is headroom for connections a request does not hold —
a Sidekiq heartbeat, a cron, a console.

Fails when neither `workers` nor `cpu` is supplied. Fails when the derived
worker count is not positive, e.g. an unparseable `cpu` quantity.

Usage: {{ include "common.dbPool" (dict "cpu" .componentValues.resources.requests.cpu "threads" 8) }}
       {{ include "common.dbPool" (dict "workers" 10) }}
*/}}
{{- define "common.dbPool" -}}
{{- $extra := .extra | default 5 -}}
{{- $workers := 0 -}}
{{- if .workers -}}
  {{- $workers = .workers | toString | float64 | ceil | int -}}
{{- else -}}
  {{- $cpu := required "common.dbPool: either `cpu` or `workers` is required" .cpu | toString -}}
  {{- if hasSuffix "m" $cpu -}}
    {{- $workers = divf (trimSuffix "m" $cpu | float64) 1000.0 | ceil | int -}}
  {{- else -}}
    {{- $workers = $cpu | float64 | ceil | int -}}
  {{- end -}}
{{- end -}}
{{- if le ($workers | int) 0 -}}
  {{- fail (printf "common.dbPool: could not derive a positive worker count (workers=%v cpu=%v); check the quantity format" .workers .cpu) -}}
{{- end -}}
{{- if .threads -}}
  {{- add (mul $workers (.threads | toString | float64 | ceil | int)) $extra -}}
{{- else -}}
  {{- add $workers $extra -}}
{{- end -}}
{{- end -}}

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
