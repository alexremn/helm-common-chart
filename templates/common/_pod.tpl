{{/*
=============================================================================
POD CONFIGURATION HELPERS
=============================================================================
*/}}

{{/*
Add node selector to pods if specified
Usage: {{ include "common.nodeSelector" .Values.myComponent }}
*/}}
{{- define "common.nodeSelector" }}
{{- include "common.passthroughField" (dict "src" . "key" "nodeSelector") }}
{{- end }}

{{/*
Add image pull secrets to pods.

Accepts two calling conventions for backward compatibility:
  1. Legacy: passes a component map directly. Looks at `.imagePullSecrets`.
  2. New:    passes `(dict "component" <map> "root" $)`. Looks at the
             component first, then falls back to `.Values.global.imagePullSecrets`.

Either form supports `imagePullSecrets` as a string, a slice of strings/maps,
or a single map with a `name` field.

Usage: {{ include "common.imagePullSecrets" (dict "component" .Values.web "root" $) }}
       {{ include "common.imagePullSecrets" .Values.web }}    {{/* legacy */}}
*/}}
{{- define "common.imagePullSecrets" -}}
{{- $component := dict -}}
{{- $globalSecrets := "" -}}
{{- $hasGlobal := false -}}
{{- if and (kindIs "map" .) (hasKey . "component") (hasKey . "root") -}}
  {{- $component = default dict .component -}}
  {{- $values := include "common._values" .root | fromYaml | default dict -}}
  {{- $g := dig "global" "imagePullSecrets" "" $values -}}
  {{- if not (kindIs "invalid" $g) -}}
    {{- if not (eq (printf "%v" $g) "") -}}
      {{- $globalSecrets = $g -}}
      {{- $hasGlobal = true -}}
    {{- end -}}
  {{- end -}}
{{- else if kindIs "map" . -}}
  {{- $component = . -}}
{{- end -}}
{{- $secrets := "" -}}
{{- $hasSecrets := false -}}
{{- if and (kindIs "map" $component) (hasKey $component "imagePullSecrets") -}}
  {{- $secrets = $component.imagePullSecrets -}}
  {{- $hasSecrets = true -}}
{{- else if $hasGlobal -}}
  {{- $secrets = $globalSecrets -}}
  {{- $hasSecrets = true -}}
{{- end -}}
{{- if $hasSecrets }}
imagePullSecrets:
{{- if kindIs "string" $secrets }}
  - name: {{ $secrets }}
{{- else if kindIs "slice" $secrets }}
  {{- toYaml $secrets | nindent 2 }}
{{- else if kindIs "map" $secrets }}
  - name: {{ $secrets.name }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Add topology spread constraints to pods if specified
Usage: {{ include "common.topologySpreadConstraints" .Values.myComponent }}
*/}}
{{- define "common.topologySpreadConstraints" }}
{{- include "common.passthroughField" (dict "src" . "key" "topologySpreadConstraints") }}
{{- end }}

{{/*
Configure the priority class name for a pod
Usage: {{ include "common.priorityClassName" .Values.myComponent }}
*/}}
{{- define "common.priorityClassName" }}
{{- include "common.passthroughField" (dict "src" . "key" "priorityClassName" "scalar" true) }}
{{- end }}

{{/*
Configure host aliases for a pod
Usage: {{ include "common.hostAliases" .Values.myComponent }}
*/}}
{{- define "common.hostAliases" }}
{{- include "common.passthroughField" (dict "src" . "key" "hostAliases") }}
{{- end }}

{{/*
Configure pod annotations
Usage: {{ include "common.podAnnotations" .Values.myComponent }}
*/}}
{{- define "common.podAnnotations" -}}
{{- if kindIs "map" . -}}
{{- if hasKey . "podAnnotations" -}}
{{- with .podAnnotations }}
annotations:
  {{- . | toYaml | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Configure init containers
Usage: {{ include "common.initContainers" .Values.myComponent }}
*/}}
{{- define "common.initContainers" }}
{{- if kindIs "map" . }}
{{- if hasKey . "initContainers" }}
initContainers:
  {{- if kindIs "slice" .initContainers }}
  {{ toYaml .initContainers | nindent 2 }}
  {{- else }}
  {{- if kindIs "map" .initContainers }}
  {{- range $name, $container := .initContainers }}
  - name: {{ $name }}
    {{ toYaml $container | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}


{{/*
Set up service account for pods.

Accepts either a plain component map (legacy) or
(dict "component" <map> "root" $ "cmp" "<component-name>"). With root,
the rails profile emits a `serviceAccountName` line so the pod stays
bound to the chart's RBAC (resolved through `common.serviceAccountName`);
other profiles omit the line and let Kubernetes apply its own default.
*/}}
{{- define "common.serviceAccount" }}
{{- $component := dict -}}
{{- $cmp := "" -}}
{{- $emitDefault := true -}}
{{- if and (kindIs "map" .) (hasKey . "component") (hasKey . "root") -}}
  {{- $component = default dict .component -}}
  {{- $cmp = default "" .cmp -}}
  {{- $profile := include "common.profile" .root -}}
  {{- if ne $profile "rails" -}}
    {{- $emitDefault = false -}}
  {{- end -}}
{{- else if kindIs "map" . -}}
  {{- $component = . -}}
{{- end -}}
{{- if and (kindIs "map" $component) (hasKey $component "serviceAccount") }}
serviceAccountName: {{ include "common.serviceAccountName" (dict "component" $component "fallback" (default "default" $cmp)) }}
{{- else if $emitDefault }}
serviceAccountName: {{ include "common.serviceAccountName" (dict "component" $component "fallback" (default "default" $cmp)) }}
{{- end }}
{{- end }}

{{/*
Standard tolerations from component config.
Usage: {{ include "common.tolerations" . }}
       {{ include "common.tolerations" (dict "component" .Values.web "root" $) }}
*/}}
{{- define "common.tolerations" -}}
{{- $component := dict -}}
{{- $profile := "rails" -}}
{{- if and (kindIs "map" .) (hasKey . "component") (hasKey . "root") -}}
  {{- $component = default dict .component -}}
  {{- $profile = include "common.profile" .root -}}
{{- else if kindIs "map" . -}}
  {{- $component = . -}}
{{- end -}}
{{- if and (kindIs "map" $component) (hasKey $component "tolerations") (gt (len $component.tolerations) 0) }}
{{- if ne $profile "rails" }}
tolerations:
{{- toYaml $component.tolerations | nindent 2 }}
{{- else }}
tolerations:
{{- range $component.tolerations }}
{{- $operator := default "Equal" .operator | toString }}
  - {{- if and (eq $operator "Exists") (not .key) }}
    {{- /* Exists without a key matches all keys; no key emitted */ -}}
    {{- else }}
    key: {{ required "Toleration key is required (or use operator: Exists)" .key | toString | quote }}
    {{- end }}
    operator: {{ $operator | quote }}
    {{- if ne $operator "Exists" }}
    {{- /* NOTE: omitting .value on an Equal-operator toleration produces
         value: "true" by convention. This is intentional for the common
         case where "true" is the intended toleration value. For other
         intended values, always supply .value explicitly. Option 1 in
         the B3 audit (fail on missing .value) is deferred to Phase C
         as a contract change. */ -}}
    value: {{ default "true" .value | toString | quote }}
    {{- end }}
    effect: {{ default "NoSchedule" .effect | toString | quote }}
    {{- with .tolerationSeconds }}
    tolerationSeconds: {{ . }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Pod-level networking and runtime knobs. Emits only fields that are set.

Strings use `with` so an empty / unset value is skipped. Booleans use
`if hasKey` so an explicit `false` is preserved — `with` treats `false`
as empty and would silently drop a deliberate disable.

Usage: {{ include "common.podRuntime" .Values.myComponent }}
*/}}
{{- define "common.podRuntime" }}
{{- if kindIs "map" . }}
{{- with .dnsPolicy }}
dnsPolicy: {{ . }}
{{- end }}
{{- with .dnsConfig }}
dnsConfig: {{ toYaml . | nindent 2 }}
{{- end }}
{{- with .runtimeClassName }}
runtimeClassName: {{ . }}
{{- end }}
{{- with .schedulerName }}
schedulerName: {{ . }}
{{- end }}
{{- if hasKey . "enableServiceLinks" }}
enableServiceLinks: {{ .enableServiceLinks }}
{{- end }}
{{- if hasKey . "shareProcessNamespace" }}
shareProcessNamespace: {{ .shareProcessNamespace }}
{{- end }}
{{- if hasKey . "automountServiceAccountToken" }}
automountServiceAccountToken: {{ .automountServiceAccountToken }}
{{- end }}
{{- if hasKey . "hostNetwork" }}
hostNetwork: {{ .hostNetwork }}
{{- end }}
{{- if hasKey . "hostPID" }}
hostPID: {{ .hostPID }}
{{- end }}
{{- if hasKey . "hostIPC" }}
hostIPC: {{ .hostIPC }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Standard pod anti-affinity configuration to spread pods across zones and nodes
Usage: {{ include "common.podAntiAffinity" (dict "svc" "my-service" "cmp" "web" "env" "prod" "Values" .Values) }}
*/}}
{{- define "common.podAntiAffinity" }}
podAntiAffinity:
{{- if .val.default }}
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app.kubernetes.io/name
          operator: In
          values:
          - {{ .svc }}
        - key: app.kubernetes.io/component
          operator: In
          values:
          - {{ .cmp }}
        - key: app.kubernetes.io/environment
          operator: In
          values:
          - {{ .env }}
      topologyKey: topology.kubernetes.io/zone
  - weight: 99
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app.kubernetes.io/name
          operator: In
          values:
          - {{ .svc }}
        - key: app.kubernetes.io/component
          operator: In
          values:
          - {{ .cmp }}
        - key: app.kubernetes.io/environment
          operator: In
          values:
          - {{ .env }}
      topologyKey: kubernetes.io/hostname
{{- end }}
{{ with .val.custom }}
  {{ toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Node affinity helper.

Accepts two input shapes:
  Map  — passed through verbatim via toYaml; supports any nodeAffinity
          structure (required/preferred, multiple matchExpressions, multi-
          value In/NotIn lists, etc.).
  Slice — legacy convenience form. Each slice entry must have fields:
          key, operator (default "In"), value (SINGLE string).
          LIMITATION: the slice form supports only one value per
          matchExpression entry. To express "key X In [v1, v2]" you must
          switch to the map form. This limitation is intentional — the
          slice form is retained for backward compatibility only. New
          consumers should use the map form.
          Deprecation to Phase C is tracked in the B3 audit (R3/N7).

Usage: {{ include "common.nodeAffinity" .Values.global.nodeAffinity }}
*/}}
{{- define "common.nodeAffinity" -}}
nodeAffinity:
{{- if kindIs "map" . }}
{{- toYaml . | nindent 2 }}
{{- else }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    {{- range . }}
      - matchExpressions:
          - key: {{ .key }}
            operator: {{ default "In" .operator }}
            values:
              - {{ .value }}
    {{- end }}
{{- end -}}
{{- end -}}

{{/*
Combined affinity helper that includes both node and pod affinities
Usage: {{ include "common.affinity" . }}
*/}}
{{- define "common.affinity" -}}
{{- $svc := .svc -}}
{{- $cmp := .cmp -}}
{{- $env := .env -}}
{{- $val := .val -}}
{{- if kindIs "map" $val -}}
{{- with $val.affinity -}}
{{- $nodeAffinity := get . "nodeAffinity" -}}
{{- $podAntiAffinity := get . "podAntiAffinity" -}}
{{- $isLegacyNodeAffinity := kindIs "slice" $nodeAffinity -}}
{{- $isLegacyPodAntiAffinity := and (kindIs "map" $podAntiAffinity) (or (hasKey $podAntiAffinity "default") (hasKey $podAntiAffinity "custom")) -}}
{{- if not (or $isLegacyNodeAffinity $isLegacyPodAntiAffinity) }}
affinity:
{{- toYaml . | nindent 2 }}
{{- else }}
affinity:
{{- with $nodeAffinity }}
{{ include "common.nodeAffinity" . | nindent 2 }}
{{- end }}
{{- if and (hasKey . "podAffinity") (not (empty .podAffinity)) }}
  podAffinity:
{{- toYaml .podAffinity | nindent 4 }}
{{- end }}
{{- with $podAntiAffinity }}
{{- if $isLegacyPodAntiAffinity }}
{{ include "common.podAntiAffinity" (dict "svc" $svc "cmp" $cmp "env" $env "val" .) | nindent 2 }}
{{- else }}
  podAntiAffinity:
{{- toYaml . | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Pod security context that can be applied to all pods.
Rails profile keeps legacy defaults; other profiles render only values.
Usage:
- Simple: {{ include "common.pod.securityContext" . }}
- With overrides: {{ include "common.pod.securityContext" (dict "runAsUser" 1000 "runAsGroup" 3000) }}
*/}}
{{- define "common.pod.securityContext" -}}
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
    "scope" "pod"
    "root" $root
    "component" $component
    "input" $input
    "wrapped" $wrapped
    "overrideKeys" (list "runAsUser" "runAsGroup" "fsGroup" "seccompType" "seccompProfile" "fsGroupChangePolicy" "supplementalGroups" "sysctls")) | fromYaml | default dict -}}
{{- if gt (len $secCtx) 0 }}
securityContext:
  {{- if hasKey $secCtx "runAsUser" }}
  runAsUser: {{ $secCtx.runAsUser }}
  {{- end }}
  {{- if hasKey $secCtx "runAsGroup" }}
  runAsGroup: {{ $secCtx.runAsGroup }}
  {{- end }}
  {{- if hasKey $secCtx "fsGroup" }}
  fsGroup: {{ $secCtx.fsGroup }}
  {{- end }}
  {{- if hasKey $secCtx "seccompProfile" }}
  seccompProfile:
    {{- toYaml $secCtx.seccompProfile | nindent 4 }}
  {{- else if hasKey $secCtx "seccompType" }}
  seccompProfile:
    type: {{ $secCtx.seccompType }}
  {{- end }}
  {{- with $secCtx.fsGroupChangePolicy }}
  fsGroupChangePolicy: {{ . }}
  {{- end }}
  {{- with $secCtx.supplementalGroups }}
  supplementalGroups:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $secCtx.sysctls }}
  sysctls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
Process and render volumes for pods
Supports multiple volume types: pvc, secret, config, emptyDir, hostPath, csi
Usage: {{ include "common.volumes" .Values.myComponent }}
*/}}
{{- define "common.volumes" }}
{{- if kindIs "map" . }}
{{- $hasVolumes := false }}
{{- if and (hasKey . "volumes") (gt (len .volumes) 0) }}
  {{- $hasVolumes = true }}
{{- end }}
{{- if hasKey . "persistence" }}
  {{- $persistence := .persistence }}
  {{- if and (kindIs "map" $persistence) (gt (len $persistence) 0) }}
    {{- $hasVolumes = true }}
  {{- else if and (kindIs "slice" $persistence) (gt (len $persistence) 0) }}
    {{- $hasVolumes = true }}
  {{- end }}
{{- end }}
{{- if $hasVolumes }}
volumes:
{{- if hasKey . "volumes" }}
{{- range $volume := .volumes }}
  - name: {{ $volume.name }}
{{- if eq (default "pvc" $volume.type) "pvc" }}
    persistentVolumeClaim:
      claimName: {{ default $volume.name $volume.claimName }}
{{- else if eq $volume.type "secret" }}
    secret:
      secretName: {{ $volume.secretName }}
      {{- if hasKey $volume "items" }}
      items:
      {{- range $item := $volume.items }}
        - key: {{ $item.key }}
          path: {{ $item.path }}
          {{- if hasKey $item "mode" }}
          mode: {{ $item.mode }}
          {{- end }}
      {{- end }}
      {{- end }}
      {{- if hasKey $volume "optional" }}
      optional: {{ $volume.optional }}
      {{- end }}
{{- else if eq $volume.type "config" }}
    configMap:
      name: {{ $volume.configMapName }}
      {{- if hasKey $volume "items" }}
      items:
      {{- range $item := $volume.items }}
        - key: {{ $item.key }}
          path: {{ $item.path }}
          {{- if hasKey $item "mode" }}
          mode: {{ $item.mode }}
          {{- end }}
      {{- end }}
      {{- end }}
      {{- if hasKey $volume "optional" }}
      optional: {{ $volume.optional }}
      {{- end }}
{{- else if eq $volume.type "emptyDir" }}
    emptyDir:
      {{- if hasKey $volume "medium" }}
      medium: {{ $volume.medium }}
      {{- end }}
      {{- if hasKey $volume "sizeLimit" }}
      sizeLimit: {{ $volume.sizeLimit }}
      {{- end }}
{{- else if eq $volume.type "hostPath" }}
    hostPath:
      path: {{ required "hostPath path is required" $volume.hostPath }}
      {{- with $volume.hostPathType }}
      type: {{ . }}
      {{- end }}
{{- else if eq $volume.type "csi" }}
    csi:
      driver: {{ required "CSI driver is required" $volume.csiDriver }}
      {{- with $volume.readOnly }}
      readOnly: {{ . }}
      {{- end }}
      {{- with $volume.fsType }}
      fsType: {{ . }}
      {{- end }}
      {{- with $volume.volumeAttributes }}
      volumeAttributes: {{ toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if hasKey . "persistence" }}
{{- $persistence := .persistence }}
{{- if kindIs "map" $persistence }}
  - name: {{ default "data" $persistence.name }}
    persistentVolumeClaim:
      claimName: {{ default $persistence.name $persistence.claimName }}
{{- else if kindIs "slice" $persistence }}
{{- range $pvc := $persistence }}
  - name: {{ required "PVC name is required" $pvc.name }}
    persistentVolumeClaim:
      claimName: {{ default $pvc.name $pvc.claimName }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
