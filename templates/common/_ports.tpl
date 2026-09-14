{{/*
=============================================================================
PORT HELPERS
Single source of truth for resolving a port definition to the number a
*Service* exposes. Both chart.service and chart.httproute must agree: an
HTTPRoute backendRef names a Service port, so any divergence produces a route
pointing at a port the Service does not expose - which still reports
ResolvedRefs=True, because the Service itself exists.

A port entry is either a scalar (the service port) or a map, in which case
precedence is servicePort > port > containerPort.
=============================================================================
*/}}

{{- define "common.ports.servicePort" -}}
{{- $port := .port -}}
{{- if kindIs "map" $port -}}
{{- coalesce $port.servicePort $port.port $port.containerPort -}}
{{- else -}}
{{- $port -}}
{{- end -}}
{{- end -}}
