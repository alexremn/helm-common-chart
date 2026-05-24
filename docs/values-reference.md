# Values reference

High-level catalog of values consumed by `common` templates, grouped by concern. For the authoritative schema (types, required fields, enums) see [`values.schema.json`](../values.schema.json). For working examples per feature see [`examples/`](../examples/).

The library does not ship its own values — your application chart's values are passed through. A typical top-level structure:

```yaml
name: <release-name>
environment: <env>
global: { ... }
app:
  replicas: 1
  image: { ... }
  ...
```

The `app` (or arbitrary component name) sub-key contains workload + container + pod + scaling + networking config. Multiple components may coexist (e.g. `app`, `worker`, `cron`).

## Workload

Keys: `workloadType`, `replicas`, `strategy`, `image`, `command`, `args`, `env`, `envFrom`, `revisionHistoryLimit`, `minReadySeconds`.

Selects the kind of workload (`Deployment` | `StatefulSet` | `DaemonSet` | `Job` | `CronJob`) and its rollout behavior. `image.repository` + `image.tag` are the most common required keys.

**CronJob default `concurrencyPolicy: Forbid`** — overrides the Kubernetes default `Allow`. Forbid is the safer choice for single-instance pipelines (no overlapping runs if a previous invocation is still going) and matches how most chart consumers use cron-style batch jobs. If your cron is parallel-safe and you want overlapping runs, set `concurrencyPolicy: Allow` per CronJob.

**Job default `backoffLimit: 0`** — overrides the Kubernetes default `6`. Jobs do not retry on failure by default; set `backoffLimit` explicitly per Job if you want retry-on-pod-failure semantics.

**Deployment default `minReadySeconds: 10`** — overrides the Kubernetes default `0`. Adds a 10-second readiness debounce to rollouts. StatefulSet and DaemonSet keep the Kubernetes default of `0`.

See: [`examples/values.generic.yaml`](../examples/values.generic.yaml), [`examples/values.daemonset.yaml`](../examples/values.daemonset.yaml).

## Container

Keys under each component: `resources` (requests/limits), `livenessProbe`, `readinessProbe`, `startupProbe`, `lifecycle`, `securityContext`, `ports`.

Per-container settings. `ports` accepts a map of name → port (e.g. `http: 8080`) and is reused for Service + ServiceMonitor wiring.

## Pod

Keys: `podSecurityContext`, `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `priorityClassName`, `serviceAccountName`, `hostNetwork`, `dnsPolicy`, `terminationGracePeriodSeconds`.

Pod-level scheduling and isolation. Affinity helpers in `templates/common/_affinities.tpl` provide presets for common topologies.

## Volumes & Storage

Keys: `volumes`, `volumeMounts`, `persistence`.

`persistence` describes a PVC the chart creates and mounts. Volumes follow the standard k8s shape with conveniences for configMap / secret refs.

See: PVC behavior is exercised in profile and statefulset variants.

## Networking

Keys: `service`, `ingress`, `networkPolicy`.

`service.type`, `service.ports` (named map matching container ports); `ingress.hosts[]`, `ingress.tls[]`, `ingress.annotations`; `networkPolicy.ingress[]` / `egress[]` with shorthand for common patterns.

See: [`examples/values.networkpolicy.yaml`](../examples/values.networkpolicy.yaml).

### `<cmp>.networkPolicy`

| Path | Type | Default | Notes |
|------|------|---------|-------|
| `<cmp>.networkPolicy.enabled` | bool | `false` | Render a NetworkPolicy for this component. |
| `<cmp>.networkPolicy.policyTypes` | list | `[Ingress]` | Standard k8s `policyTypes`. To restrict egress, set `[Ingress, Egress]` and supply `egress` rules. |
| `<cmp>.networkPolicy.ingress` | list | `[]` | Standard k8s ingress rules. |
| `<cmp>.networkPolicy.egress` | list | unset | Standard k8s egress rules. Empty list under Egress policyType means deny-all egress. |
| `<cmp>.networkPolicy.annotations` | map | `{}` | Extra metadata annotations. |

**Security note:** The default `policyTypes: [Ingress]` is permissive on egress
(matches Kubernetes default). For egress restriction, set `policyTypes:
[Ingress, Egress]` and add explicit egress rules. v3.0 will flip the default
to `[Ingress, Egress]` with a deny-all default.

## Autoscaling & Disruption

Keys: `hpa`, `vpa`, `scaledObject`, `pdb`.

- `hpa` — standard HorizontalPodAutoscaler with metrics shorthand
- `vpa` — VerticalPodAutoscaler (requires VPA operator in cluster)
- `scaledObject` — KEDA `ScaledObject` for event-driven autoscaling; pair with `triggerAuthentication` for secret-backed triggers
- `pdb` — PodDisruptionBudget

See: [`examples/values.hpa.yaml`](../examples/values.hpa.yaml), [`examples/values.vpa.yaml`](../examples/values.vpa.yaml).

## Observability

Keys: `serviceMonitor`, `podMonitor`, `prometheusRule`.

Prometheus Operator CRDs. ServiceMonitor scrapes endpoints exposed by your Service; PodMonitor scrapes pods directly; PrometheusRule defines alerting/recording rules.

See: [`examples/values.servicemonitor.yaml`](../examples/values.servicemonitor.yaml), [`examples/values.prometheusrule.yaml`](../examples/values.prometheusrule.yaml).

## Config & Secrets

Keys: `configMap`, `secret`, `externalSecret`.

- `configMap` — inline data, mounted as env or file
- `secret` — opaque secret, mounted as env or file
- `externalSecret` — `ExternalSecret` CRD (requires External Secrets Operator); references a remote backing store

## RBAC

Keys: `serviceAccount`, `role`, `roleBinding`, `clusterRole`, `clusterRoleBinding`.

Each component may declare its own ServiceAccount and bind to Roles/ClusterRoles. Defaults to the workload's default ServiceAccount if unset.

See: [`examples/values.rbac.yaml`](../examples/values.rbac.yaml).

## Profiles

Keys: `profile.name`, `profile.<language>.*`.

Language/runtime profile defaults (`go`, `python`, generic). Applies opinionated defaults for resource shape, probes, and security context. Override individual keys per component.

See: [`examples/values.profile-go.yaml`](../examples/values.profile-go.yaml), [`examples/values.profile-python.yaml`](../examples/values.profile-python.yaml).

## Misc

- `priorityClass` — define a `PriorityClass` (cluster-scoped). Map of name → spec.
- `hooks` — Helm hook weights/annotations for release-time orchestration.
- `compat.legacySelectorLabels` — opt-in to older selector label scheme for charts migrated from `werf`.

## Where things live in templates

| Concern | Template | Helper |
|---|---|---|
| Workload composition | `templates/_deployment.tpl`, `_statefulset.tpl`, `_daemonset.tpl`, `_job.tpl`, `_cronjob.tpl` | `templates/common/_workload.tpl` |
| Pod spec | (inside workloads) | `templates/common/_pod.tpl` |
| Container spec | (inside pod) | `templates/common/_container.tpl` |
| Labels/annotations/naming | (everywhere) | `templates/common/_general.tpl`, `_helpers.tpl` |
| Affinity / topology | (inside pod) | `templates/common/_affinities.tpl` |
| Language profile defaults | (inside container) | `templates/common/_profile.tpl` |
