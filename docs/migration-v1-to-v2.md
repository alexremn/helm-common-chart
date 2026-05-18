# Migrating from v1.x to v2.0.0

This document compares **v1.x** (pre-public, Rails/AWS-flavored defaults) with **v2.0.0** (first public release with neutral defaults) and lists every behavior or input change a consumer must handle on upgrade.

Pin `version: "^1.0.0"` to stay on v1. Pin `version: "^2.0.0"` to opt into v2.

## At a glance

| Area | v1.x behavior | v2.0.0 behavior |
|---|---|---|
| Default profile | `rails` (probe `/health_check/full`, `runAsUser: 1000`, envFrom phantoms, Sidekiq probe, Rails metric relabels) | `generic` (no framework opinions) |
| `environment` label | `app.kubernetes.io/environment`, also in `spec.selector.matchLabels` (immutable) | `helm.sh/environment`, **not** in selectors |
| Default `serviceAccountName` (rails profile) | Literal `"default"` baked into pod spec | Omitted; admission applies cluster default |
| ServiceAccount token mount | `automountServiceAccountToken: true` default | `automountServiceAccountToken: false` default |
| PVC `storageClassName` | Defaults to `gp3` (AWS-only) | Omitted; cluster default StorageClass applies |
| Ingress class auto-mapping | `internal` → `nginx-internal`, `external` → `nginx` (Hubstaff-only) | No auto-map; `className` required per entry or via `global.ingress.className` |
| ExternalSecret `secretStore` | Defaults to `secrets-manager` (AWS) with kind `ClusterSecretStore` | **Required** — no default |
| KEDA Prometheus trigger `serverAddress` | Defaults to `http://prometheus-prometheus.prometheus.svc.cluster.local:9090` | **Required** — set `global.prometheusEndpoint` or per-trigger |
| `common.generateName` suffix | Random alphanumeric per render (non-deterministic) | Caller must pass `suffix` (typically `.Release.Revision`) |
| Image without tag/digest | Falls back to `:latest` (silent) | `fail`s at render time |
| RBAC↔Pod SA-name resolution | Diverged (pod = `"default"`, RBAC = `$cmp`) — silent no-op bindings | Both routed through `common.serviceAccountName` |

## Features

v2 is **not** a feature-add release. All workload kinds, networking primitives, autoscalers, observability resources, RBAC, storage, and secrets supported in v1.x remain in v2 with the same template entry points. The release is a hardening + neutralization pass:

- Removed framework-specific defaults so the library is cluster-portable.
- Closed silent-failure paths (latest tags, undefined SAs, unknown profiles, bad probes — see below).
- Refactor-only collapses (passthrough helpers, RBAC paths, securityContext merge) — render output unchanged.

### Render-equivalent refactors (no behavior change)

| Helper / template | Change | Caller impact |
|---|---|---|
| `common.passthroughField` | Replaces `common.command`, `args`, `resources`, `lifecycle`, `nodeSelector`, `topologySpreadConstraints`, `priorityClassName`, `hostAliases`, `podAnnotations` | None — original helpers delegate |
| `common.workload.podSpec` | Boilerplate emit blocks collapsed into table-driven loop | None |
| `common.workload.annotations` | Werf + user annotations unified across all 5 workloads (DaemonSet now emits werf annotations like the others) | DaemonSet consumers using werf now get the werf annotations they were missing |
| `common._securityContextMerge` | Shared between pod and container helpers | None |
| `_rbac.tpl` | Three paths (namespaced / cluster-scoped / top-level) routed through one renderer | None |

## Required input changes

If your values file relies on any of the v1 defaults below, **v2 will fail to render** (or render a broken manifest) unless you set the field explicitly.

### Hard `fail`s in v2 (template error if unset)

| Helper / template | Field | Where to set |
|---|---|---|
| `common.image.toString` | image tag or digest (or `.Chart.AppVersion`) | `.<cmp>.image.tag` |
| `common.generateName` | `suffix` arg | Pass `.Release.Revision` at call site |
| `_extsecret.tpl` | `secretStore` | `secrets.<name>.secretStore` |
| `_scaledobject.tpl` (prometheus trigger) | `serverAddress` | `global.prometheusEndpoint` or per-trigger override |
| `_profile.tpl` | recognized profile name | `global.profile` must be one of `generic`, `rails`, `python`, `go` (unknown name → `fail` with valid list) |

### Defaults removed (silent acceptance → cluster default)

| Field | v1.x default | v2.0.0 default |
|---|---|---|
| `<cmp>.persistence.storageClass` | `gp3` | unset (cluster default StorageClass) |
| `<cmp>.ingress.<entry>.className` (map-style) | `nginx-internal` / `nginx` by key | unset → `global.ingress.className` → unset |
| Pod `serviceAccountName` (rails profile) | `"default"` | unset (admission applies SA `default`) |
| ServiceAccount `automountServiceAccountToken` | `true` | `false` |
| `imagePullPolicy` (when tag is `latest`) | `IfNotPresent` | unchanged in v2 — but `:latest` itself now requires explicit opt-in (see image fail) |

### Label schema (immutable on existing workloads)

- `app.kubernetes.io/environment` → `helm.sh/environment`.
- `helm.sh/environment` is **not** included in `spec.selector.matchLabels`.

Kubernetes refuses in-place selector mutation. Existing Deployments, StatefulSets, and DaemonSets created under v1 must be **deleted and re-created** during the v2 upgrade. Plan for traffic drain (PDB, service-traffic shift) and coordinate with on-call.

## Opt back into v1 behavior

If you can't migrate every concern at once, set `global.profile: rails` to restore the bundle of Rails defaults:

```yaml
global:
  profile: rails
```

This re-enables: probe path `/health_check/full`, runAsUser/Group 1000/3000, envFrom phantoms `config`/`secrets`, Sidekiq probe command, and the Rails-flavored PodMonitor metric relabels.

The following v2 changes are **independent of profile** and cannot be reverted via `global.profile`:

- `helm.sh/environment` label rename and selector removal
- `automountServiceAccountToken: false` default on `chart.serviceAccount`
- PVC `storageClassName` default removal
- Ingress auto-class mapping removal
- ExternalSecret `secretStore` requirement
- KEDA `serverAddress` requirement
- `generateName` deterministic-suffix requirement
- Image-without-tag `fail`

Each must be addressed in your application chart's values.

## Upgrade checklist

1. **Pick a profile.** Add `global.profile: rails` if you depend on Rails defaults; otherwise accept `generic`.
2. **Plan a workload re-create.** Delete + apply every Deployment / StatefulSet / DaemonSet (label-schema break). Coordinate with PDBs and traffic.
3. **Audit secret stores.** Set `secrets.<name>.secretStore` on every `ExternalSecret`.
4. **Audit ingresses.** Set `className` per entry or `global.ingress.className` globally if you used the map-style ingress with `internal`/`external` keys.
5. **Set `global.prometheusEndpoint`** if any chart uses KEDA prometheus triggers.
6. **Set `serviceAccount.automount: true`** on workloads that call the Kubernetes API.
7. **Set `storageClass`** on PVCs, or accept your cluster's default.
8. **Pass `suffix: .Release.Revision`** to every `common.generateName` call.
9. **Set `.<cmp>.image.tag` or `.digest`** explicitly on every component. The `:latest` fallback is gone.
10. **Re-render and diff.** `helm template` v2 vs v1 with your values; expect changes only in the rows above.

## Reference

- Audit covering every v1 → v2 finding: `docs/superpowers/audits/2026-05-17-template-audit.md` (local; not shipped).
- Working examples: [`examples/`](../examples/).
- Schema: [`values.schema.json`](../values.schema.json).
