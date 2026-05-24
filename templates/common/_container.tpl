{{/*
=============================================================================
CONTAINER CONFIGURATION HELPERS
=============================================================================
*/}}

{{/*
Process container command
Usage: {{ include "common.command" .Values.myComponent }}
*/}}
{{- define "common.command" }}
{{- include "common.passthroughField" (dict "src" . "key" "command") }}
{{- end }}

{{/*
Process container args
Usage: {{ include "common.args" .Values.myComponent }}
*/}}
{{- define "common.args" }}
{{- include "common.passthroughField" (dict "src" . "key" "args") }}
{{- end }}

{{/*
Process container resources
Usage: {{ include "common.resources" .Values.myComponent }}
*/}}
{{- define "common.resources" }}
{{- include "common.passthroughField" (dict "src" . "key" "resources") }}
{{- end }}

{{/*
Process container lifecycle
Usage: {{ include "common.lifecycle" .Values.myComponent }}
*/}}
{{- define "common.lifecycle" }}
{{- include "common.passthroughField" (dict "src" . "key" "lifecycle") }}
{{- end }}

{{/*
Process ports for containers
Usage: {{ include "common.ports" .Values.myComponent }}
*/}}
{{- define "common.ports" }}
{{- if kindIs "map" . }}
{{- if hasKey . "ports" }}
ports:
{{- /* Iterate over sorted keys so render order is part of the contract,
       independent of Sprig/Go map-iteration internals. Keeps golden tests
       stable across Helm minor-version bumps. */ -}}
{{- $portMap := .ports }}
{{- range $name := keys $portMap | sortAlpha }}
{{- $value := index $portMap $name }}
{{- if kindIs "map" $value }}
- name: {{ $name }}
  containerPort: {{ $value.containerPort | int }}
  protocol: {{ default "TCP" $value.protocol }}
  {{- with $value.hostPort }}
  hostPort: {{ . }}
  {{- end }}
{{- else }}
- name: {{ $name }}
  containerPort: {{ $value | int }}
  protocol: TCP
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
=============================================================================
PROBE HELPERS
=============================================================================
*/}}

{{/*
Define a probe with intelligent defaults
Usage: {{ include "common.probe" .Values.myComponent }}
*/}}
{{- define "common.probe" -}}
{{- /* If the caller passed a `_root` key (workload.podSpec does), use it to
       resolve the profile and global overrides. Otherwise fall back to the
       component map itself, which silently resolves to the rails profile —
       preserving v1.3.1 behavior for any direct caller that doesn't pass _root. */ -}}
{{- $root := default . ._root -}}
{{- $phase := default "" ._phase -}}
{{- /* `.` here is the component map merged with `_root`/`_phase` keys —
       passing it as `component` lets common.profile see a per-component
       `profile:` override before falling back to global. */ -}}
{{- $profile := include "common.profile" (dict "root" $root "component" .) -}}
{{- $defaults := index (include "common.profile.defaults" $root | fromYaml) $profile -}}
{{- $values := include "common._values" $root | fromYaml | default dict -}}
{{- $globalProbe := dig "global" "probe" dict $values -}}
{{- $probeDefaults := $defaults.probe -}}
{{- $shared := dig "probes" dict . -}}
{{- $perPhase := dict -}}
{{- if and (ne $phase "") (kindIs "map" $shared) (hasKey $shared $phase) -}}
  {{- $perPhase = index $shared $phase -}}
  {{- if not (kindIs "map" $perPhase) -}}{{- $perPhase = dict -}}{{- end -}}
{{- end -}}
{{- /* Resolution per field, lowest to highest priority:
         profile-default  →  .Values.global.probe.<field>  →  .probes.<field>  →  .probes.<phase>.<field>
       Uses `dig` (not `coalesce`) so falsy-but-valid values (0, []) are honored. */ -}}
{{- $probe := dict }}
{{- $fields := list "type" "path" "command" "port" "initialDelaySeconds" "periodSeconds" "failureThreshold" "timeoutSeconds" }}
{{- range $field := $fields }}
  {{- $defaultVal := index $probeDefaults $field }}
  {{- $resolved := dig $field (dig $field (dig $field $defaultVal $globalProbe) $shared) $perPhase }}
  {{- $_ := set $probe $field $resolved }}
{{- end }}

{{- if eq $probe.type "exec" -}}
exec:
  command:
    {{- toYaml $probe.command | nindent 4 }}
{{- else if eq $probe.type "http" -}}
httpGet:
  path: {{ $probe.path }}
  port: {{ $probe.port }}
  {{- $headers := dig "httpHeaders" (dig "httpHeaders" nil $shared) $perPhase }}
  {{- with $headers }}
  httpHeaders:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- else if eq $probe.type "tcp" -}}
tcpSocket:
  port: {{ $probe.port }}
{{- else if eq $probe.type "grpc" -}}
grpc:
  port: {{ $probe.port }}
  {{- $service := dig "service" (dig "service" nil $shared) $perPhase }}
  {{- with $service }}
  service: {{ . }}
  {{- end }}
{{- else -}}
  {{- fail (printf "common.probe: unknown probe type %q. Must be one of: exec, http, tcp, grpc." $probe.type) -}}
{{- end }}
initialDelaySeconds: {{ $probe.initialDelaySeconds }}
periodSeconds: {{ $probe.periodSeconds }}
failureThreshold: {{ $probe.failureThreshold }}
timeoutSeconds: {{ $probe.timeoutSeconds }}
{{- $successThreshold := dig "successThreshold" (dig "successThreshold" nil $shared) $perPhase }}
{{- with $successThreshold }}
successThreshold: {{ . }}
{{- end }}
{{- $tgs := dig "terminationGracePeriodSeconds" (dig "terminationGracePeriodSeconds" nil $shared) $perPhase }}
{{- with $tgs }}
terminationGracePeriodSeconds: {{ . }}
{{- end }}
{{- end -}}

{{/*
Configure liveness, readiness, and (optionally) startup probes.
Can be disabled with probes.enabled=false. Per-phase override blocks are read
from .probes.startup, .probes.liveness, .probes.readiness; each falls back to
shared .probes.<field> then global.probe.<field> then profile default.
Usage: {{ include "common.probes" .Values.myComponent }}
*/}}
{{- define "common.probes" -}}
{{- /* Resolve probes shape: bool false disables; map with enabled=false disables.
       Use `dig` (not `default`) so falsy-but-valid `enabled: false` is honored —
       Sprig's `default` treats false as empty and would silently flip it back to true. */ -}}
{{- $probesVal := dig "probes" dict . -}}
{{- $disabled := false -}}
{{- if kindIs "bool" $probesVal -}}
  {{- $disabled = not $probesVal -}}
{{- else if kindIs "map" $probesVal -}}
  {{- $disabled = eq (dig "enabled" true $probesVal) false -}}
{{- end -}}
{{- if $disabled -}}
{{- /* probes disabled — emit nothing */ -}}
{{- else -}}
{{- if and (kindIs "map" $probesVal) (hasKey $probesVal "startup") }}
startupProbe:
  {{- include "common.probe" (merge (dict "_phase" "startup") .) | nindent 2 }}
{{- end }}
readinessProbe:
  {{- include "common.probe" (merge (dict "_phase" "readiness") .) | nindent 2 }}
livenessProbe:
  {{- include "common.probe" (merge (dict "_phase" "liveness") .) | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
=============================================================================
ENVIRONMENT VARIABLES AND REFERENCES
=============================================================================
*/}}

{{/*
Define a secret reference environment variable
Usage: {{ include "common.env.secretRef" (dict "name" "DB_PASSWORD" "secretName" "my-secret" "key" "password") }}
*/}}
{{- define "common.env.secretRef" }}
  - name: {{ .name }}
    valueFrom:
      secretKeyRef:
        name: {{ .secretName }}
        key: {{ .key }}
        {{- with .optional }}
        optional: {{ . }}
        {{- end }}
{{- end }}

{{/*
Define a configmap reference environment variable
Usage: {{ include "common.env.configMapRef" (dict "name" "LOG_LEVEL" "configMapName" "app-config" "key" "log-level") }}
*/}}
{{- define "common.env.configMapRef" }}
  - name: {{ .name }}
    valueFrom:
      configMapKeyRef:
        name: {{ .configMapName }}
        key: {{ .key }}
        {{- with .optional }}
        optional: {{ . }}
        {{- end }}
{{- end }}

{{/*
Define a field reference environment variable
Usage: {{ include "common.env.fieldRef" (dict "name" "POD_NAME" "fieldPath" "metadata.name") }}
*/}}
{{- define "common.env.fieldRef" }}
  - name: {{ .name }}
    valueFrom:
      fieldRef:
        fieldPath: {{ .fieldPath }}
{{- end }}

{{/*
Process environment variables from a dictionary.

SECURITY: env values are rendered through Helm's `tpl`. Any Go-template
syntax in a value is executed. Treat env values as a code surface — only
set them from a trusted values source. For multi-tenant setups, gate
untrusted env values behind a separate helper or strip template syntax
before passing them in.

This helper accepts two call shapes:

  (a) PREFERRED — wrapped dict from internal callers:
        (dict "Values" $.Values "Release" $.Release "Chart" $.Chart
              "componentValues" $componentValues)
      Consumer env templates can address `.Values`, `.Release`, `.Chart`,
      and `.componentValues` on the curated context. Sibling components
      are reachable via `.Values.<other>` but the full helm root (`$`)
      and built-ins like `$.Files`, `$.Template`, `$.Capabilities` are
      NOT exposed.

  (b) LEGACY — bare component-values map:
        {{ include "common.envs" .Values.myComponent }}
      BREAKING for legacy shape: in this mode `.Values`, `.Release` and
      `.Chart` are passed to `tpl` as EMPTY dicts. Consumer templates that
      reference `{{ .Values.foo }}` etc. silently render as empty string.
      This is the deliberate cost of closing the F2 injection surface for
      callers that did not migrate to shape (a). Migrate to shape (a) to
      regain root access.

Usage (shape a, preferred):
  {{ include "common.envs" (dict
       "Values" $.Values "Release" $.Release "Chart" $.Chart
       "componentValues" .Values.myComponent) }}

Usage (shape b, legacy):
  {{ include "common.envs" .Values.myComponent }}
*/}}
{{- define "common.envs" }}
{{- /* F2 follow-up: tighten dual-shape detection. A caller is treated as
       shape (a) only when ALL FOUR curated-context keys are present and
       map-typed: Values, Release, Chart, componentValues. If any are
       missing or not map-typed, fall back to shape (b) — the input is
       the component map itself. This prevents an external caller whose
       component map happens to contain a `componentValues:` sub-map from
       being misclassified as wrapped. */ -}}
{{- if kindIs "map" . }}
{{- $componentValues := . }}
{{- $rootValues := dict }}
{{- $rootRelease := dict }}
{{- $rootChart := dict }}
{{- $isWrapped := and (hasKey . "Values") (hasKey . "Release") (hasKey . "Chart") (hasKey . "componentValues") }}
{{- if $isWrapped }}
  {{- /* .Values is map[string]interface{} from chartutil; .componentValues
         is a values sub-map; both must be map-typed. .Release and .Chart
         are Helm structs (not maps) — presence via hasKey is sufficient. */ -}}
  {{- $isWrapped = and (kindIs "map" .Values) (kindIs "map" .componentValues) }}
{{- end }}
{{- if $isWrapped }}
  {{- $componentValues = .componentValues }}
  {{- $rootValues = .Values }}
  {{- $rootRelease = .Release }}
  {{- $rootChart = .Chart }}
{{- end }}
{{- if hasKey $componentValues "env" }}
{{- $tplCtx := dict "Values" $rootValues "Release" $rootRelease "Chart" $rootChart "componentValues" $componentValues }}
env:
{{- range $key, $value := $componentValues.env }}
{{- if kindIs "map" $value }}
{{- if hasKey $value "valueFrom" }}
- name: {{ $key }}
  valueFrom: {{ toYaml $value.valueFrom | nindent 4 }}
{{- else }}
- name: {{ $key }}
  value: {{ tpl (toString $value.value) $tplCtx | quote }}
{{- end }}
{{- else }}
- name: {{ $key }}
  value: {{ tpl (toString $value) $tplCtx | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
EnvFrom helper supporting both global and component-specific configs/secrets
Usage: {{ include "common.envFrom" (dict "svc" .Values.myComponent "global" .Values.global) }}
*/}}
{{- define "common.envFrom" }}
{{- $entries := list }}
{{- /* Profile-aware phantom defaults: under rails, defaultConfigName="config"
       and defaultSecretName="secrets" preserve v1.3.1 behavior. Under generic /
       python / go they are "" so no phantom default is emitted — only explicit
       names. */ -}}
{{- $profileDefaults := dict -}}
{{- if .root -}}
  {{- $profile := include "common.profile" (dict "root" .root "component" (default dict .svc)) -}}
  {{- $profileDefaults = index (include "common.profile.defaults" .root | fromYaml) $profile -}}
{{- end -}}
{{- $defaultConfigName := dig "envFrom" "defaultConfigName" "config" $profileDefaults -}}
{{- $defaultSecretName := dig "envFrom" "defaultSecretName" "secrets" $profileDefaults -}}
{{- /* Phantom defaults are emitted with optional: true so a missing
       ConfigMap/Secret in the cluster does not crash pod startup. */ -}}
{{- $defaultConfigList := list -}}
{{- if ne $defaultConfigName "" -}}
  {{- $defaultConfigList = list (dict "name" $defaultConfigName "optional" true) -}}
{{- end -}}
{{- $defaultSecretList := list -}}
{{- if ne $defaultSecretName "" -}}
  {{- $defaultSecretList = list (dict "name" $defaultSecretName "optional" true) -}}
{{- end }}

{{/* Append global defaults/config where present */}}
{{- if and (kindIs "map" .global) (hasKey .global "envFrom") }}
  {{- with .global.envFrom }}
    {{- range .configs | default $defaultConfigList }}
      {{- if kindIs "string" . }}
        {{- $entries = append $entries (dict "type" "configMapRef" "name" .) }}
      {{- else }}
        {{- $entry := dict "type" "configMapRef" "name" .name }}
        {{- if hasKey . "optional" }}
          {{- $_ := set $entry "optional" .optional }}
        {{- end }}
        {{- $entries = append $entries $entry }}
      {{- end }}
    {{- end }}
    {{- range .secrets | default $defaultSecretList }}
      {{- if kindIs "string" . }}
        {{- $entries = append $entries (dict "type" "secretRef" "name" .) }}
      {{- else }}
        {{- $entry := dict "type" "secretRef" "name" .name }}
        {{- if hasKey . "optional" }}
          {{- $_ := set $entry "optional" .optional }}
        {{- end }}
        {{- $entries = append $entries $entry }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{/* Append component-specific entries */}}
{{- if and (kindIs "map" .svc) (hasKey .svc "envFrom") }}
  {{- with .svc.envFrom }}
    {{- range .configs | default (list) }}
      {{- if kindIs "string" . }}
        {{- $entries = append $entries (dict "type" "configMapRef" "name" .) }}
      {{- else }}
        {{- $entry := dict "type" "configMapRef" "name" .name }}
        {{- if hasKey . "optional" }}
          {{- $_ := set $entry "optional" .optional }}
        {{- end }}
        {{- $entries = append $entries $entry }}
      {{- end }}
    {{- end }}
    {{- range .secrets | default (list) }}
      {{- if kindIs "string" . }}
        {{- $entries = append $entries (dict "type" "secretRef" "name" .) }}
      {{- else }}
        {{- $entry := dict "type" "secretRef" "name" .name }}
        {{- if hasKey . "optional" }}
          {{- $_ := set $entry "optional" .optional }}
        {{- end }}
        {{- $entries = append $entries $entry }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- if gt (len $entries) 0 }}
envFrom:
{{- range $entry := $entries }}
  - {{ $entry.type }}:
      name: {{ $entry.name | quote }}
      {{- if hasKey $entry "optional" }}
      optional: {{ $entry.optional }}
      {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Container security context that can be applied to all containers.
Rails profile keeps legacy defaults; other profiles render only values.
Usage:
- Simple: {{ include "common.container.securityContext" . }}
- With overrides: {{ include "common.container.securityContext" (dict "readOnlyRootFilesystem" true) }}
*/}}
{{- define "common.container.securityContext" -}}
{{- $input := default dict . -}}
{{- $component := $input -}}
{{- $root := $input -}}
{{- $wrapped := false -}}
{{- if and (kindIs "map" $input) (hasKey $input "component") -}}
  {{- $component = default dict $input.component -}}
  {{- $root = default dict $input.root -}}
  {{- $wrapped = true -}}
{{- end -}}
{{- $secCtx := include "common._securityContext.merge" (dict
    "scope" "container"
    "root" $root
    "component" $component
    "input" $input
    "wrapped" $wrapped
    "overrideKeys" (list "allowPrivilegeEscalation" "runAsNonRoot" "privileged" "readOnlyRootFilesystem" "capabilities" "localhostProfile" "seccompProfile" "procMount" "seLinuxOptions" "windowsOptions")) | fromYaml | default dict -}}
{{- if gt (len $secCtx) 0 }}
securityContext:
  {{- if hasKey $secCtx "allowPrivilegeEscalation" }}
  allowPrivilegeEscalation: {{ $secCtx.allowPrivilegeEscalation }}
  {{- end }}
  {{- if hasKey $secCtx "runAsNonRoot" }}
  runAsNonRoot: {{ $secCtx.runAsNonRoot }}
  {{- end }}
  {{- if hasKey $secCtx "privileged" }}
  privileged: {{ $secCtx.privileged }}
  {{- end }}
  {{- if hasKey $secCtx "readOnlyRootFilesystem" }}
  readOnlyRootFilesystem: {{ $secCtx.readOnlyRootFilesystem }}
  {{- end }}
  {{- with $secCtx.capabilities }}
  capabilities:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if hasKey $secCtx "seccompProfile" }}
  seccompProfile:
    {{- toYaml $secCtx.seccompProfile | nindent 4 }}
  {{- else }}
    {{- with $secCtx.localhostProfile }}
  seccompProfile:
    type: Localhost
    localhostProfile: {{ . }}
    {{- end }}
  {{- end }}
  {{- with $secCtx.procMount }}
  procMount: {{ . }}
  {{- end }}
  {{- with $secCtx.seLinuxOptions }}
  seLinuxOptions:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $secCtx.windowsOptions }}
  windowsOptions:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
Process and render volumeMounts for containers
Only explicit volumeMounts and persistence entries are mounted.
Usage: {{ include "common.volumeMounts" .Values.myComponent }}
*/}}
{{- define "common.volumeMounts.spec" -}}
- name: {{ required "Volume name is required" .name }}
  {{- if hasKey . "mountPath" }}
  mountPath: {{ .mountPath }}
  {{- else }}
  mountPath: /mnt/{{ .name }}
  {{- end }}
  {{- if hasKey . "subPath" }}
  subPath: {{ .subPath }}
  {{- end }}
  {{- if hasKey . "readOnly" }}
  readOnly: {{ .readOnly }}
  {{- end }}
{{- end }}

{{- define "common.volumeMounts" }}
{{- if kindIs "map" . }}
{{- $hasVolumeMounts := false }}
{{- if and (hasKey . "volumeMounts") (gt (len .volumeMounts) 0) }}
  {{- $hasVolumeMounts = true }}
{{- end }}
{{- if hasKey . "persistence" }}
  {{- $persistence := .persistence }}
  {{- if and (kindIs "map" $persistence) (gt (len $persistence) 0) }}
    {{- $hasVolumeMounts = true }}
  {{- else if and (kindIs "slice" $persistence) (gt (len $persistence) 0) }}
    {{- $hasVolumeMounts = true }}
  {{- end }}
{{- end }}
{{- if $hasVolumeMounts }}
volumeMounts:
{{- if hasKey . "volumeMounts" }}
{{- range $volumeMount := .volumeMounts }}
{{- include "common.volumeMounts.spec" $volumeMount | nindent 2 }}
{{- end }}
{{- end }}
{{- if hasKey . "persistence" }}
{{- $persistence := .persistence }}
{{- if kindIs "map" $persistence }}
{{- include "common.volumeMounts.spec" $persistence | nindent 2 }}
{{- else if kindIs "slice" $persistence }}
{{- range $pvc := $persistence }}
{{- include "common.volumeMounts.spec" $pvc | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
