{{/*
=============================================================================
AFFINITY TEMPLATES
This file contains templates for Kubernetes pod and node affinities.

Usage examples:
Node affinity: {{ include "common.affinities.nodes" (dict "type" "soft" "key" "node-role" "values" (list "worker")) }}
Pod affinity: {{ include "common.affinities.pods" (dict "type" "soft" "component" "web" "context" $) }}
Pod anti-affinity: {{ include "common.affinities.podAntiAffinity" (dict "component" "web" "context" $) }}
=============================================================================
*/}}

{{/*
Default topologyKey with intelligent fallback mechanism
Usage: {{ include "common.affinities.topologyKey" (dict "topologyKey" "topology.kubernetes.io/zone") }}
*/}}
{{- define "common.affinities.topologyKey" -}}
{{- $defaultTopologyKey := "kubernetes.io/hostname" -}}
{{- $standardTopologyKeys := list "kubernetes.io/hostname" "topology.kubernetes.io/zone" "topology.kubernetes.io/region" -}}
{{- if .topologyKey -}}
  {{- if has .topologyKey $standardTopologyKeys -}}
    {{- .topologyKey -}}
  {{- else -}}
    {{- /* Warn if non-standard topology key is used - this is a no-op in production */ -}}
    {{- $defaultTopologyKey -}}
  {{- end -}}
{{- else -}}
  {{- $defaultTopologyKey -}}
{{- end -}}
{{- end -}}

{{/*
=============================================================================
NODE AFFINITY TEMPLATES
=============================================================================
*/}}

{{/*
Soft (preferred) node affinity definition
Usage: {{ include "common.affinities.nodes.soft" (dict "key" "instance-type" "values" (list "c5.large" "c5.xlarge") "weight" 50) }}
*/}}
{{- define "common.affinities.nodes.soft" -}}
preferredDuringSchedulingIgnoredDuringExecution:
  - preference:
      matchExpressions:
        - key: {{ .key }}
          operator: In
          values:
            {{- range .values }}
            - {{ . | quote }}
            {{- end }}
    weight: {{ default 1 .weight }}
{{- end -}}

{{/*
Hard (required) node affinity definition
Usage: {{ include "common.affinities.nodes.hard" (dict "key" "instance-type" "values" (list "c5.large" "c5.xlarge")) }}
*/}}
{{- define "common.affinities.nodes.hard" -}}
requiredDuringSchedulingIgnoredDuringExecution:
  nodeSelectorTerms:
    - matchExpressions:
        - key: {{ .key }}
          operator: In
          values:
            {{- range .values }}
            - {{ . | quote }}
            {{- end }}
{{- end -}}

{{/*
General node affinity definition with specified type (soft or hard)
Usage: {{ include "common.affinities.nodes" (dict "type" "soft" "key" "instance-type" "values" (list "c5.large" "c5.xlarge") "weight" 50) }}
*/}}
{{- define "common.affinities.nodes" -}}
  {{- if eq .type "soft" }}
    {{- include "common.affinities.nodes.soft" . -}}
  {{- else if eq .type "hard" }}
    {{- include "common.affinities.nodes.hard" . -}}
  {{- else }}
    {{- fail (printf "Unknown affinity type: %s. Must be 'soft' or 'hard'" .type) -}}
  {{- end -}}
{{- end -}}

{{/*
=============================================================================
POD AFFINITY TEMPLATES
=============================================================================
*/}}

{{/*
Soft (preferred) pod affinity/anti-affinity definition
Usage: {{ include "common.affinities.pods.soft" (dict "component" "web" "extraMatchLabels" .Values.extraMatchLabels "topologyKey" "topology.kubernetes.io/zone" "context" $) }}
*/}}
{{- define "common.affinities.pods.soft" -}}
{{- $component := default "" .component -}}
{{- $extraMatchLabels := default (dict) .extraMatchLabels -}}
{{- $weight := default 1 .weight | int -}}
preferredDuringSchedulingIgnoredDuringExecution:
  - podAffinityTerm:
      labelSelector:
        matchLabels: {{- (include "common.labels.matchLabels" .context) | nindent 10 }}
          {{- if not (empty $component) }}
          app.kubernetes.io/component: {{ $component }}
          {{- end }}
          {{- range $key, $value := $extraMatchLabels }}
          {{ $key }}: {{ $value | quote }}
          {{- end }}
      topologyKey: {{ include "common.affinities.topologyKey" (dict "topologyKey" .topologyKey) }}
    weight: {{ $weight }}
{{- end -}}

{{/*
Hard (required) pod affinity/anti-affinity definition
Usage: {{ include "common.affinities.pods.hard" (dict "component" "web" "extraMatchLabels" .Values.extraMatchLabels "topologyKey" "topology.kubernetes.io/zone" "context" $) }}
*/}}
{{- define "common.affinities.pods.hard" -}}
{{- $component := default "" .component -}}
{{- $extraMatchLabels := default (dict) .extraMatchLabels -}}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels: {{- (include "common.labels.matchLabels" .context) | nindent 8 }}
        {{- if not (empty $component) }}
        app.kubernetes.io/component: {{ $component }}
        {{- end }}
        {{- range $key, $value := $extraMatchLabels }}
        {{ $key }}: {{ $value | quote }}
        {{- end }}
    topologyKey: {{ include "common.affinities.topologyKey" (dict "topologyKey" .topologyKey) }}
{{- end -}}

{{/*
General pod affinity/anti-affinity definition with specified type (soft or hard)
Usage: {{ include "common.affinities.pods" (dict "type" "soft" "component" "web" "extraMatchLabels" .Values.extraMatchLabels "topologyKey" "topology.kubernetes.io/zone" "context" $) }}
*/}}
{{- define "common.affinities.pods" -}}
  {{- if eq .type "soft" }}
    {{- include "common.affinities.pods.soft" . -}}
  {{- else if eq .type "hard" }}
    {{- include "common.affinities.pods.hard" . -}}
  {{- else }}
    {{- fail (printf "Unknown affinity type: %s. Must be 'soft' or 'hard'" .type) -}}
  {{- end -}}
{{- end -}}

{{/*
Complete pod anti-affinity configuration with multi-zone and multi-node distribution
Provides a balanced distribution of pods across zones (high weight) and nodes (medium weight)
Usage: {{ include "common.affinities.podAntiAffinity" (dict "component" "web" "context" $) }}
*/}}
{{- define "common.affinities.podAntiAffinity" -}}
podAntiAffinity:
  {{- include "common.affinities.pods.soft" (dict
    "component" .component
    "weight" 100
    "topologyKey" "topology.kubernetes.io/zone"
    "context" .context) | nindent 2 }}
  {{- include "common.affinities.pods.soft" (dict
    "component" .component
    "weight" 50
    "topologyKey" "kubernetes.io/hostname"
    "context" .context) | nindent 2 }}
{{- end -}}

{{/*
Combined affinity helper for complete affinity configuration
Usage: {{ include "common.affinities.complete" (dict "component" "web" "nodeAffinityType" "soft" "nodeKey" "node-role" "nodeValues" (list "worker") "context" $) }}
*/}}
{{- define "common.affinities.complete" -}}
{{- $nodeAffinityType := default "soft" .nodeAffinityType -}}
{{- $nodeKey := default "" .nodeKey -}}
{{- $nodeValues := default (list) .nodeValues -}}
affinity:
  {{- if and $nodeKey $nodeValues }}
  nodeAffinity:
    {{- include "common.affinities.nodes" (dict "type" $nodeAffinityType "key" $nodeKey "values" $nodeValues) | nindent 4 }}
  {{- end }}

  {{- include "common.affinities.podAntiAffinity" (dict "component" .component "context" .context) | nindent 2 }}
{{- end -}}
