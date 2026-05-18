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
Resolve the environment label (`app.kubernetes.io/environment`).
Lookup order:
  1. .env passed via helper context
  2. .Values.global.environment / .Values.global.env
  3. .Values.environment / .Values.env
  4. .Values.werf.env (legacy fallback)
  5. literal "default"
*/}}
{{- define "common.environment" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- coalesce .env (dig "global" "environment" nil $values) (dig "global" "env" nil $values) (dig "environment" nil $values) (dig "env" nil $values) (dig "werf" "env" nil $values) "default" -}}
{{- end }}

{{/*
DNS-safe component name for resource metadata (`-` separated).
*/}}
{{- define "common.componentName" -}}
{{- (required "Component name is required" .cmp) | replace "_" "-" -}}
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
  svc, cmp, env, Values, Release, Chart, version (optional), extraLabels (optional)

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
app.kubernetes.io/name: {{ $svc }}
{{- if $cmp }}
app.kubernetes.io/component: {{ $cmp }}
{{- end }}
{{- if $env }}
helm.sh/environment: {{ $env }}
{{- end }}
{{- if $instance }}
app.kubernetes.io/instance: {{ $instance }}
{{- end }}
{{- with .version }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with .extraLabels }}
{{ toYaml . | nindent 0 }}
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
{{- if $instance }}
app.kubernetes.io/instance: {{ $instance }}
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
Decide whether werf-specific annotations should be emitted.
Resolution order:
  1. .Values.global.werf.annotations (explicit opt-in/out)
  2. true if `.Values.werf.name` AND `.Values.werf.env` both set
     (preserves the legacy behavior for charts still on werf values)
  3. false otherwise
*/}}
{{- define "common.werf.annotationsEnabled" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $explicit := dig "global" "werf" "annotations" nil $values -}}
{{- $werfName := dig "werf" "name" nil $values -}}
{{- $werfEnv := dig "werf" "env" nil $values -}}
{{- if not (kindIs "invalid" $explicit) -}}
{{ $explicit }}
{{- else if and $werfName $werfEnv -}}
true
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Werf-specific Deployment / StatefulSet annotations. Emitted only when
`common.werf.annotationsEnabled` resolves truthy.
*/}}
{{- define "common.annotations.werf" -}}
{{- $enabled := eq (include "common.werf.annotationsEnabled" .) "true" -}}
{{- if $enabled -}}
werf.io/no-activity-timeout: {{ default "6m" .timeout | quote }}
werf.io/failures-allowed-per-replica: {{ default "3" .failures | quote }}
{{- end }}
{{- end -}}

{{/*
Process annotations from a dictionary or nested structure.
Usage: {{ include "common.annotations" .Values.myComponent.annotations }}
*/}}
{{- define "common.annotations" -}}
{{- if kindIs "map" . -}}
{{- if hasKey . "annotations" -}}
{{- with .annotations }}
annotations:
  {{- . | toYaml | nindent 2 }}
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
Deep merge maps.
Usage: {{ include "common.mergeValues" (dict "src" $srcMap "dest" $destMap) }}
*/}}
{{- define "common.mergeValues" }}
{{- $src := .src }}
{{- $dest := .dest }}
{{ toYaml (merge $dest $src) }}
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
{{- if and $user $password }}
{{ printf "%s://%s:%s@%s:%s/%s%s" $type $user $password $host $port $name $options }}
{{- else }}
{{ printf "%s://%s:%s/%s%s" $type $host $port $name $options }}
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
{{- $name := .name | lower | replace "." "-" | replace "_" "-" | trunc (default 63 .maxLength) | regexReplaceAll "-+$" "" }}
{{ $name }}
{{- end }}

{{/*
Indent multiline strings with a specified number of spaces.
Usage: {{ include "common.indent" (dict "value" $multilineString "spaces" 2) }}
*/}}
{{- define "common.indent" }}
{{- $lines := splitList "\n" .value }}
{{- $spaces := default 2 .spaces | int }}
{{- $indent := "" }}
{{- range $i, $_ := until $spaces }}
  {{- $indent = printf "%s " $indent }}
{{- end }}
{{- range $i, $line := $lines }}
  {{- if $i }}
    {{ printf "\n%s%s" $indent $line }}
  {{- else }}
    {{ $line }}
  {{- end }}
{{- end }}
{{- end }}
