{{/*
=============================================================================
SERVICE TEMPLATE
This template renders a standard Kubernetes Service with common configuration.
=============================================================================
*/}}

{{/*
Render the `spec.ports` list of a Service.

`mode` controls which optional fields are emitted:
- "full"     — main Service: appProtocol, nodePort when type=NodePort.
- "simple"   — extraServices / headless: name/port/targetPort/protocol only.

Usage:
  {{ include "chart.service.ports" (dict "ports" $ports "serviceConfig" $serviceConfig "mode" "full") }}
*/}}
{{- define "chart.service.ports" -}}
{{- $ports := .ports -}}
{{- $serviceConfig := default dict .serviceConfig -}}
{{- $mode := default "full" .mode -}}
{{- range $name, $port := $ports }}
    {{- $servicePort := $port }}
    {{- $targetPort := $name }}
    {{- $protocol := "TCP" }}
    {{- $appProtocol := "" }}
    {{- if kindIs "map" $port }}
      {{- $servicePort = coalesce $port.servicePort $port.port $port.containerPort }}
      {{- $protocol = default "TCP" $port.protocol }}
      {{- $appProtocol = default "" $port.appProtocol }}
      {{- if hasKey $port "targetPort" }}
        {{- $targetPort = $port.targetPort }}
      {{- else if hasKey $port "containerPort" }}
        {{- $targetPort = $port.containerPort }}
      {{- end }}
    {{- end }}
    {{- if not $servicePort }}
      {{- fail (printf "Port definition for %s must provide a numeric value (or servicePort/port/containerPort in map form)" $name) }}
    {{- end }}
    - name: {{ $name }}
      port: {{ $servicePort | int }}
      targetPort: {{ $targetPort }}
      protocol: {{ $protocol }}
      {{- if and (eq $mode "full") $appProtocol }}
      appProtocol: {{ $appProtocol }}
      {{- end }}
      {{- if and (eq $mode "full") (eq (default "" $serviceConfig.type) "NodePort") $serviceConfig.nodePorts (hasKey $serviceConfig.nodePorts $name) }}
      nodePort: {{ index $serviceConfig.nodePorts $name }}
      {{- end }}
{{- end -}}
{{- end -}}

{{- define "chart.service" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $serviceConfig := dig "service" dict $componentValues }}
{{- $ports := $componentValues.ports | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- if not $ports }}
{{ fail "No ports defined for service. Please define at least one port in the component values." }}
{{- else }}

apiVersion: v1
kind: Service
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" $serviceConfig | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  type: {{ dig "type" "ClusterIP" $serviceConfig }}
  {{- with $serviceConfig.clusterIP }}
  clusterIP: {{ . }}
  {{- end }}
  {{- with $serviceConfig.sessionAffinity }}
  sessionAffinity: {{ . }}
  {{- end }}
  {{- with $serviceConfig.sessionAffinityConfig }}
  sessionAffinityConfig: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $serviceConfig.internalTrafficPolicy }}
  internalTrafficPolicy: {{ . }}
  {{- end }}
  {{- with $serviceConfig.externalTrafficPolicy }}
  externalTrafficPolicy: {{ . }}
  {{- end }}
  {{- with $serviceConfig.ipFamilyPolicy }}
  ipFamilyPolicy: {{ . }}
  {{- end }}
  {{- with $serviceConfig.ipFamilies }}
  ipFamilies: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $serviceConfig.publishNotReadyAddresses }}
  publishNotReadyAddresses: {{ . }}
  {{- end }}
  ports:
  {{- include "chart.service.ports" (dict "ports" $ports "serviceConfig" $serviceConfig "mode" "full") }}
  selector:
    {{- include "common.labels.matchLabels" $labelCtx | nindent 4 }}
  {{- with $serviceConfig.externalIPs }}
  externalIPs: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $serviceConfig.loadBalancerIP }}
  loadBalancerIP: {{ . }}
  {{- end }}
  {{- with $serviceConfig.loadBalancerSourceRanges }}
  loadBalancerSourceRanges: {{ toYaml . | nindent 4 }}
  {{- end }}

{{- /* Sibling Service objects via service.extraServices: { name -> overrides }. */ -}}
{{- range $extraName, $extra := dig "extraServices" dict $serviceConfig }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ printf "%s-%s" $cmp $extraName | replace "_" "-" }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $extra.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ dig "type" "ClusterIP" $extra }}
  {{- with $extra.clusterIP }}
  clusterIP: {{ . }}
  {{- end }}
  ports:
  {{- $extraPorts := $extra.ports | default $ports }}
  {{- include "chart.service.ports" (dict "ports" $extraPorts "mode" "simple") }}
  selector:
    {{- include "common.labels.matchLabels" $labelCtx | nindent 4 }}
{{- end }}
{{ end }}
{{- end }}

{{/*
Headless service template
Usage: {{ include "chart.service.headless" (dict "svc" "service-name" "cmp" "component" "Values" .Values) }}
*/}}
{{- define "chart.service.headless" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $serviceConfig := dig "service" "headless" dict $componentValues }}
{{- $ports := $componentValues.ports | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- if not $ports }}
{{ fail "No ports defined for service. Please define at least one port in the component values." }}
{{- else }}

apiVersion: v1
kind: Service
metadata:
  name: {{ $cmp }}-headless
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
    service.kubernetes.io/headless: "true"
  {{- $ann := include "common.annotations" $serviceConfig | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  {{- include "chart.service.ports" (dict "ports" $componentValues.ports "mode" "simple") }}
  selector:
    {{- include "common.labels.matchLabels" $labelCtx | nindent 4 }}
  publishNotReadyAddresses: {{ default false $serviceConfig.publishNotReadyAddresses }}
{{ end }}
{{- end }}
