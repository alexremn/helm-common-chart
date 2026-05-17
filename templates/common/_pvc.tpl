{{/*
Render the spec section of a PersistentVolumeClaim.
Expects:
- $: the global context
- .pvc: the PVC config map (e.g. $persistence or $pvc)
*/}}
{{- define "common.pvc.spec" -}}
{{- if .accessModes -}}
accessModes:
  {{- toYaml .accessModes | nindent 2 }}
{{- else -}}
accessModes: [{{ default "ReadWriteOnce" .accessMode }}]
{{- end }}
resources:
  requests:
    storage: {{ required "Volume size is required" .size | quote }}
storageClassName: {{ default "gp3" .storageClass }}
{{- with .selector }}
selector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .volumeName }}
volumeName: {{ . }}
{{- end }}
{{- with .volumeMode }}
volumeMode: {{ . }}
{{- end }}
{{- with .dataSource }}
dataSource:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .dataSourceRef }}
dataSourceRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
