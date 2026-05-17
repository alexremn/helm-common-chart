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
    {{- $result := "" -}}
    {{- range $i := until . -}}
        {{- $base := shuffle "0123456789abcdef" -}}
        {{- $i_curr := (randNumeric 1) | int -}}
        {{- $i_next := add $i_curr 1 | int -}}
        {{- $rand_hex := substr $i_curr $i_next $base -}}
        {{- $result = print $result $rand_hex -}}
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
  {{- $namespace  := default .Release.Namespace .ns -}}
  {{- $value      := .value -}}
  {{- if and $key $name -}}
    {{- $configMap := (lookup "v1" "ConfigMap" $namespace $name).data -}}
    {{- if and $configMap (index $configMap $key) -}}
      {{- $value := index $configMap $key -}}
      {{- printf "%s: %s" $key ($value | toString | quote) -}}
    {{- else -}}
      {{- printf "%s: %s" $key ($value | toString | quote) -}}
    {{- end -}}
  {{- else -}}
    {{- printf "%s: %s" $key ($value | toString | quote) -}}
  {{- end -}}
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
Retrieve a secret value from Kubernetes
Usage: {{ include "secrets.retrieve" (dict "name" "secret-name" "key" "KEY_NAME" "type" "full" "ns" .Release.Namespace) }}
*/}}
{{- define "secrets.retrieve" -}}
  {{- $type       := default "full" .type -}}
  {{- $name       := default "secrets" .name -}}
  {{- $key        := required "Key is required" .key -}}
  {{- $namespace  := default .Release.Namespace .ns -}}
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
Define a secret value with generator and lookup capability
Usage: {{ include "secrets.define" (dict "name" "secret-name" "key" "KEY_NAME" "value" "default-value" "type" "full" "var" "base" "ns" .Release.Namespace) }}
*/}}
{{- define "secrets.define" -}}
  {{- $type       := default "full" .type -}}
  {{- $var        := default "base" .var -}}
  {{- $name       := default "secrets" .name -}}
  {{- $key        := required "Key is required" .key -}}
  {{- $namespace  := default .Release.Namespace .ns -}}
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
Generate a deterministic name for resources like jobs
Usage: {{ include "generateName" (dict "name" "job-name" "suffix" .Release.Revision) }}
*/}}
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

{{- define "generateName" -}}
  {{- $name := required "Name is required" .name }}
  {{- $suffix := .suffix }}
  {{- if not $suffix }}
    {{- $suffix = required "generateName: suffix is required (pass .Release.Revision for a per-revision suffix, or any deterministic string)" .suffix }}
  {{- end }}
  {{- printf "%s-%s" $name (toString $suffix) }}
{{- end -}}
