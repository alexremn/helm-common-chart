# Breaking changes

## v2.0.0 — 2026-05-17

v2 is a clean break from v1.x to remove framework-specific defaults and
unsafe fallbacks that were baked into the library chart's behavior. Pin
to `^1.0.0` to stay on v1; pin `^2.0.0` to opt in to the new defaults.

| # | Change | Migration |
|---|---|---|
| 1 | Default profile flips `rails` → `generic` | Set `global.profile: rails` to keep v1.x rails defaults (probe path `/health_check/full`, envFrom phantoms `config`/`secrets`, `runAsUser: 1000`, `runAsGroup: 3000`, Sidekiq probe command, metric relabelings). |
| 2 | `app.kubernetes.io/environment` label removed, replaced by `helm.sh/environment`. Also dropped from `spec.selector.matchLabels`. | Kubernetes refuses in-place selector mutation. Existing Deployments / StatefulSets / DaemonSets must be deleted and re-created. |
| 3 | `serviceAccountName` no longer defaults to literal `"default"` on the rails profile | Pod-side and RBAC-side now both route through `common.serviceAccountName`. Resolution: `.serviceAccount.name` → component name. Set `.<cmp>.serviceAccount.name: default` to retain the v1 behavior. |
| 4 | ServiceAccount `automountServiceAccountToken` defaults to `false` | Workloads that call the K8s API must set `.<cmp>.serviceAccount.automount: true`. |
| 5 | PVC `storageClassName: gp3` default removed | Set `.<cmp>.persistence.storageClass` explicitly, or rely on the cluster's default StorageClass. |
| 6 | Ingress auto-class mapping (`internal` → `nginx-internal`, `external` → `nginx`) removed | Set `ingressClassName` per-entry via `.<cmp>.ingress.<entry>.className`, or globally via `global.ingress.className`. |
| 7 | ExternalSecret `secretStore` is now required | Set `secrets.<name>.secretStore` explicitly. No more fallback to `secrets-manager`. |
| 8 | KEDA Prometheus trigger `serverAddress` is now required | Set `global.prometheusEndpoint` explicitly when any ScaledObject uses a prometheus trigger. |
| 9 | `common.generateName` requires an explicit suffix | Pass `.Release.Revision` (typical) or any deterministic string. Random-suffix fallback removed — names no longer drift across `helm upgrade`. |
| 10 | `common.image.toString` fails when no tag, digest, or `.Chart.AppVersion` is set | Set `.<cmp>.image.tag` (or `.digest`) explicitly. No more silent `:latest`. |

## Upgrade checklist

1. Add `global.profile: rails` to your values file if you depend on Rails-flavored defaults — or migrate to vanilla defaults.
2. Plan a delete + re-create for every workload (labels schema change). Coordinate with PDBs and traffic.
3. Audit every `ingress.<entry>` and every `ExternalSecret` for explicit `className` / `secretStore`.
4. Set `global.prometheusEndpoint` if you use KEDA prometheus triggers.
5. Set `serviceAccount.automount: true` on workloads that need a token.
6. Set `storageClass` on PVCs or accept your cluster's default.
7. Pass `suffix: .Release.Revision` to any `generateName` call.
