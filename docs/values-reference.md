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

- **DaemonSet:** `revisionHistoryLimit`, `updateStrategy`, `minReadySeconds` are read from the flat `<cmp>.*` keys (symmetric with Deployment/StatefulSet); the legacy `<cmp>.daemonSet.*` sub-map is honored as a fallback when the flat key is unset.

**CronJob default `concurrencyPolicy: Forbid`** — overrides the Kubernetes default `Allow`. Forbid is the safer choice for single-instance pipelines (no overlapping runs if a previous invocation is still going) and matches how most chart consumers use cron-style batch jobs. If your cron is parallel-safe and you want overlapping runs, set `concurrencyPolicy: Allow` per CronJob.

**Job default `backoffLimit: 0`** — overrides the Kubernetes default `6`. Jobs do not retry on failure by default; set `backoffLimit` explicitly per Job if you want retry-on-pod-failure semantics.

**Deployment default `minReadySeconds: 10`** — overrides the Kubernetes default `0`. Adds a 10-second readiness debounce to rollouts. StatefulSet and DaemonSet keep the Kubernetes default of `0`.

**Kubernetes version floor for opt-in batch fields.** On clusters older than a field's support floor the apiserver silently drops it (the chart declares `kubeVersion: ">=1.24-0"`, so it does not enforce these): CronJob `timeZone` needs **k8s ≥1.27** (GA; alpha 1.25 — UTC is used below that), and Job/CronJob `podFailurePolicy` needs **k8s ≥1.26** (beta). Set these only on clusters at or above those versions.

See: [`examples/values.generic.yaml`](../examples/values.generic.yaml), [`examples/values.daemonset.yaml`](../examples/values.daemonset.yaml).

## Container

Keys under each component: `resources` (requests/limits), `probes`, `lifecycle`, `securityContext`, `ports`.

Per-container settings. `ports` accepts a map of name → port (e.g. `http: 8080`) and is reused for Service + ServiceMonitor wiring.

### Probes

The library renders `livenessProbe`, `readinessProbe`, and (optionally) `startupProbe` per container from a single `<cmp>.probes` block. Each field is resolved per-phase with this chain (lowest to highest priority):

```
profile default  →  global.probe.<field>  →  <cmp>.probes.<field>  →  <cmp>.probes.<phase>.<field>
```

The probe transport is selected by `type` (a flat keyword, **not** a `httpGet`/`tcpSocket`/`exec` sub-map):

| `type` | Required fields | Rendered Kubernetes shape |
|--------|-----------------|---------------------------|
| `http` (default for built-in profiles) | `path`, `port` | `httpGet: { path, port, httpHeaders? }` |
| `tcp` | `port` | `tcpSocket: { port }` |
| `exec` | `command` (list of strings) | `exec: { command }` |
| `grpc` | `port`, optional `service` | `grpc: { port, service? }` |

Unknown `type` values fail the render with `common.probe: unknown probe type ...`.

Per-component / per-phase keys:

| Path | Type | Default | Notes |
|------|------|---------|-------|
| `<cmp>.probes.enabled` | bool | `true` | `false` (or shorthand `<cmp>.probes: false`) disables all three phases. |
| `<cmp>.probes.<phase>.type` | string | profile default | One of `http`, `tcp`, `exec`, `grpc`. |
| `<cmp>.probes.<phase>.path` | string | profile default | HTTP probe path (`type: http`). |
| `<cmp>.probes.<phase>.port` | string\|int | profile default (`http`) | Port name or number. Used by `http`, `tcp`, `grpc`. |
| `<cmp>.probes.<phase>.command` | list | profile default (`[]`) | Exec probe argv (`type: exec`). |
| `<cmp>.probes.<phase>.httpHeaders` | list | unset | Extra HTTP headers for `type: http`. |
| `<cmp>.probes.<phase>.service` | string | unset | gRPC service name for `type: grpc`. |
| `<cmp>.probes.<phase>.initialDelaySeconds` | int | profile default (`0`) | |
| `<cmp>.probes.<phase>.periodSeconds` | int | profile default (`10`) | |
| `<cmp>.probes.<phase>.timeoutSeconds` | int | profile default (varies) | |
| `<cmp>.probes.<phase>.failureThreshold` | int | profile default (varies) | |
| `<cmp>.probes.<phase>.successThreshold` | int | unset | Only emitted when set. |
| `<cmp>.probes.<phase>.terminationGracePeriodSeconds` | int | unset | Only emitted when set. |

`<phase>` is one of `liveness`, `readiness`, `startup`. `startup` is only rendered when `<cmp>.probes.startup` is explicitly set; `liveness` and `readiness` are always rendered (unless probes are disabled).

`<cmp>.probes.<field>` (without a phase) sets a shared override that applies to all three phases. `.Values.global.probe.<field>` sets a chart-wide override below the per-component value. Resolution uses `dig` so falsy-but-valid values (`0`, `[]`) are honored.

Profile defaults (probe `type`, `path`, `port`, thresholds) live in `templates/common/_profile.tpl` under `common.profile.defaults`. See [Profiles](#profiles).

## Pod

Keys: `securityContext.pod`, `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `priorityClassName`, `serviceAccountName`, `hostNetwork`, `hostPID`, `hostIPC`, `dnsPolicy`, `dnsConfig`, `runtimeClassName`, `schedulerName`, `terminationGracePeriodSeconds`.

Pod-level scheduling and isolation. The pod `securityContext` is layered over the chart-wide `global.security` posture (see [Security posture](#security-posture)), not applied by the runtime profile. Affinity helpers in `templates/common/_affinities.tpl` provide presets for common topologies. `hostNetwork`, `hostPID`, and `hostIPC` share the host's namespaces and are a privilege-escalation surface — they are off unless explicitly set, and only emitted when the key is present.

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

**`hpa.kind` / `hpa.apiVersion` — scaleTargetRef contract.**
`chart.hpa` defaults `scaleTargetRef.kind` to `Deployment` and `scaleTargetRef.apiVersion` to `apps/v1`. For StatefulSet (or any non-Deployment) workloads you **must** set `<component>.hpa.kind` explicitly — the library cannot infer the workload kind. Allowed values: `Deployment`, `StatefulSet`, `ReplicaSet`. Any other value fails fast at render time with a clear message. Override `hpa.apiVersion` only when targeting a CRD or a non-`apps/v1` resource. Example:

```yaml
stateful:
  hpa:
    kind: StatefulSet        # required — library cannot auto-detect
    minReplicas: 2
    maxReplicas: 10
    metrics: [...]
```

`hpa` and `scaling` (KEDA ScaledObject) are mutually exclusive on the same component — `chart.hpa` fails fast if both are set.

**`pdb.unhealthyPodEvictionPolicy` requires k8s ≥1.27.** The field is alpha (off) in 1.26 and absent in 1.24/1.25; on the chart's declared `>=1.24-0` floor the apiserver silently prunes it below 1.27, so the requested eviction policy is not enforced. Set it only on clusters at or above 1.27.

See: [`examples/values.hpa.yaml`](../examples/values.hpa.yaml), [`examples/values.vpa.yaml`](../examples/values.vpa.yaml).

## Observability

Keys: `serviceMonitor`, `podMonitor`, `prometheusRule`.

Prometheus Operator CRDs. ServiceMonitor scrapes endpoints exposed by your Service; PodMonitor scrapes pods directly; PrometheusRule defines alerting/recording rules.

See: [`examples/values.servicemonitor.yaml`](../examples/values.servicemonitor.yaml), [`examples/values.prometheusrule.yaml`](../examples/values.prometheusrule.yaml).

## Config & Secrets

Keys: `configMap`, `secret`, `externalSecret`, `envFrom`.

- `configMap` — inline data, mounted as env or file
- `secret` — opaque secret, mounted as env or file
- `externalSecret` — `ExternalSecret` CRD (requires External Secrets Operator); references a remote backing store
- `envFrom` — list of ConfigMap/Secret refs projected into container env

**Templating env values & Secret `stringData` (`tpl` opt-out).** By default, `<cmp>.env` values and native Secret `stringData` are rendered through Helm's `tpl` so consumers can interpolate (e.g. `"{{ .Release.Namespace }}"`). In multi-tenant setups where values come from untrusted sources, disable this to emit values verbatim:

- `global.tpl.envValues: false` — chart-wide opt-out.
- `<cmp>.envRaw: true` — per-component opt-out (also honored on native Secret entries as `<secret>.envRaw: true`).

When disabled, `{{ ... }}` in a value is emitted literally (no evaluation, no injection surface).

### `envFrom` shape and rails-profile phantom defaults

`envFrom` is **not** a flat list of Kubernetes `envFrom` entries. It is a structured map with two keys:

```yaml
<cmp>:
  envFrom:
    configs:                 # rendered as configMapRef entries
      - my-config            # bare string -> { configMapRef: { name: my-config } }
      - name: opt-config     # map form lets you set optional
        optional: true
    secrets:                 # rendered as secretRef entries
      - my-secret
      - name: opt-secret
        optional: false
```

`.Values.global.envFrom.{configs,secrets}` works the same way and is emitted before component-specific entries.

**Rails profile injects phantom defaults.** When the resolved profile (per [Profile resolution](#profile-resolution)) is `rails` and `.global.envFrom` is set (the helper only activates when `global.envFrom` exists), the rendered pod spec gets two implicit entries — one ConfigMap, one Secret — if you do not supply your own:

```yaml
envFrom:
  - configMapRef:
      name: config
      optional: true
  - secretRef:
      name: secrets
      optional: true
```

The hardcoded names (`config`, `secrets`) come from the rails profile's `envFrom.defaultConfigName` / `defaultSecretName` (see `templates/common/_profile.tpl`). `optional: true` means the workload starts even if those ConfigMap/Secret objects are absent — preserving v1.3.1 behavior.

**Opting out:** supply explicit empty lists at the global level:

```yaml
global:
  envFrom:
    configs: []
    secrets: []
```

Both `global` and per-component lists are appended to the rendered `envFrom` (not merged), so a custom list at `global.envFrom.configs` replaces the phantom default. Generic / python / go profiles have empty `defaultConfigName` and `defaultSecretName`, so no phantom defaults are emitted under those profiles.

## Ingress

Keys: `<cmp>.ingress` (map or list form), `<cmp>.ingress.<entry>.className`,
`global.ingress.className`, `global.ingress.annotations`.

### IngressClass resolution

`spec.ingressClassName` is set from, in priority order:

```
<cmp>.ingress.<entry>.className  ->  global.ingress.className
```

The legacy `kubernetes.io/ingress.class` **annotation is NOT auto-translated**
into `spec.ingressClassName`. If you set it under `annotations:` it is passed
through verbatim as an annotation (for controllers that still read it), but it
will not populate `ingressClassName`. To target a class the modern way, set
`className` (per entry) or `global.ingress.className`. This is deliberate — the
annotation has been deprecated upstream since Kubernetes 1.18 and the chart does
not silently map between the two mechanisms.

## Monitoring

Keys: `<cmp>.serviceMonitor`, `<cmp>.podMonitor`, `prometheusRules`, `global.monitoring.releaseLabel`.

Per-component `serviceMonitor` / `podMonitor` render a Prometheus Operator
ServiceMonitor / PodMonitor; they are mutually exclusive per component (the
render fails fast if both are enabled).

### `namespaceSelector` scope

Both monitors default to scraping only the **release namespace**:

```yaml
namespaceSelector:
  matchNames:
    - <Release.Namespace>
```

To scrape across **all namespaces**, set an explicit empty selector — this is the
Prometheus Operator convention for cluster-wide discovery:

```yaml
web:
  serviceMonitor:
    enabled: true
    portName: metrics
    namespaceSelector: {}      # cluster-wide; overrides the release-namespace default
```

The same `namespaceSelector: {}` opt-in applies to `<cmp>.podMonitor`.

### Discovery label

Set `global.monitoring.releaseLabel` so kube-prometheus-stack's default
`release` selector matches these monitors. See [Global knobs](#global-knobs).

## RBAC

Keys: `serviceAccount`, `role`, `roleBinding`, `clusterRole`, `clusterRoleBinding`.

Each component may declare its own ServiceAccount and bind to Roles/ClusterRoles. Defaults to the workload's default ServiceAccount if unset.

### ServiceAccount fields

| Path | Type | Default | Notes |
|------|------|---------|-------|
| `<cmp>.serviceAccount.create` | bool | `true` | Render the ServiceAccount object. `false` skips it. |
| `<cmp>.serviceAccount.enabled` | bool | `true` | Alias gate; `false` also skips creation. |
| `<cmp>.serviceAccount.name` | string | component name | SA name. With `create: false` it points at an externally-managed SA. |
| `<cmp>.serviceAccount.automount` | bool | `false` | **Single source of truth** for token mounting. Sets `automountServiceAccountToken` on **both** the ServiceAccount object and the pod spec, so it is effective whether the pod uses this SA or the namespace `default` SA. Default `false` = no token mounted (secure-by-default). |
| `<cmp>.serviceAccount.annotations` | map | `{}` | Annotations on the SA object. |

**`serviceAccountName` guard.** The pod only pins a `serviceAccountName` the
cluster will actually have: when the SA is not created (`create: false` /
`enabled: false`) and no explicit `name` is given, the line is omitted and the
pod falls back to the namespace `default` SA instead of a dangling reference.

> **Upgrade note:** token automount is now governed solely by
> `serviceAccount.automount`. A pod-level `automountServiceAccountToken` set
> directly on a component is no longer read — move the value to
> `serviceAccount.automount`.

See: [`examples/values.rbac.yaml`](../examples/values.rbac.yaml).

## Profiles

Keys: `global.profile`, `<cmp>.profile`.

Language/runtime profile defaults (`generic`, `rails`, `python`, `go`). Applies opinionated defaults for probes, podMonitor relabelings, and envFrom phantoms. Override individual keys per component as usual.

**Security context is a separate axis** — profiles no longer carry a `securityContext`. See [Security posture](#security-posture).

See: [`examples/values.profile-go.yaml`](../examples/values.profile-go.yaml), [`examples/values.profile-python.yaml`](../examples/values.profile-python.yaml).

### Profile resolution

Profile is resolved per component using this chain:

```
<cmp>.profile  ->  global.profile  ->  "generic"
```

- `<cmp>.profile`: per-component override (v2.1+). Lets you mix profiles
  across components in a single chart (e.g., a generic-profile Python web
  pod alongside a rails-profile background worker).
- `global.profile`: chart-wide default. Backward-compatible with v2.0.
- Fallback default: `"generic"`.

Allowed values: `rails`, `python`, `go`, `generic`. Invalid values fail
loudly at render time (no silent fallback).

| Path | Type | Default | Notes |
|------|------|---------|-------|
| `global.profile` | string | `generic` | Chart-wide default. |
| `<cmp>.profile` | string | inherits `global.profile` | Per-component override (v2.1+). |

Example:

```yaml
global:
  profile: generic        # chart-wide default

web:
  # inherits global -> generic
  image: { repository: ghcr.io/example/api, tag: "1.0.0" }

worker:
  profile: rails          # per-component override
  image: { repository: ghcr.io/example/worker, tag: "1.0.0" }
```

See the `mixed-profiles` smoke fixture
([`tests/smoke/values-mixed-profiles.yaml`](../tests/smoke/values-mixed-profiles.yaml))
for a worked end-to-end example.

## Security posture

Key: `global.security`.

The pod/container `securityContext` defaults are a **separate axis** from the
runtime profile — any profile can run with any posture. Selected chart-wide via
`global.security`:

| Posture | Container hardening | Use when |
|---|---|---|
| `minimal` (**default**) | `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, pod-level `seccompProfile: RuntimeDefault` (`runAsNonRoot`/`readOnlyRootFilesystem` stay opt-in) | charts that write to disk or run as root |
| `generic` | `runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`, `capabilities.drop: [ALL]` | hardened workloads |

Both postures are overridable per-scope by `global.securityContext.<scope>` and
`<cmp>.securityContext.<scope>` (layered after the posture, last wins).

Allowed values: `minimal`, `generic`. Invalid values fail loudly at render time.

| Path | Type | Default | Notes |
|------|------|---------|-------|
| `global.security` | string | `minimal` | Chart-wide securityContext posture. |

```yaml
global:
  profile: rails        # runtime defaults (probes, envFrom, ...)
  security: generic     # hardened securityContext, independent of profile
```

> **Upgrade note:** before this split, the `generic`/`python`/`go` profiles
> enforced the hardened context by default and `rails` injected
> `runAsUser: 1000` / `runAsGroup: 3000`. Posture now defaults to `minimal`
> (no enforced hardening) and carries no uid/gid. Set `global.security: generic`
> to restore hardening; set `runAsUser`/`runAsGroup` explicitly under
> `securityContext.pod` if you relied on the old rails uid/gid.

## Misc

- `priorityClasses` — define `PriorityClass` objects (cluster-scoped). Map of name → spec. Rendered by `chart.priorityclass`.
- `hooks` — Helm hook weights/annotations for release-time orchestration.
- `compat.legacySelectorLabels` — opt-in to older selector label scheme for charts migrated from `werf`.
- **Top-level passthrough resource names.** `prometheusRules`, `networkPolicies`, `configs`, `nativeSecrets`, `priorityClasses`, `triggerAuthentications`, and `rbac` use the consumer map **key verbatim** as `metadata.name` — the chart does NOT prefix the release/app name. Consumers own and namespace these names to avoid collisions when two charts share a namespace. These shared resources are not stamped an `app.kubernetes.io/component` label.

### Global knobs

Chart-wide values consumed across multiple templates. Each path is read via `dig "global" ...` so the keys are always optional and missing values resolve to the documented default.

| Path | Type | Default | Notes |
|---|---|---|---|
| `global.profile` | string | `generic` | Chart-wide profile default. See [Profile resolution](#profile-resolution). |
| `global.security` | string | `minimal` | Chart-wide securityContext posture (`minimal` \| `generic`), independent of `profile`. See [Security posture](#security-posture). |
| `global.name` | string | unset | Falls back to `app.name` / top-level `name` / `werf.name` / chart name. Used as the application identifier. |
| `global.environment` | string | unset | Falls back to top-level `environment` / `env` / `werf.env` / `default`. Used as the deploy environment identifier. |
| `global.image` | map | unset | Default image map (`repository`, `tag`, `pullPolicy`) used when a component does not set its own. |
| `global.imagePullPolicy` | string | unset | Cluster-wide default pull policy fallback (after component-level, before `Always`/`IfNotPresent` heuristic). |
| `global.imagePullSecrets` | list | unset | Image pull secrets appended to every pod spec after per-component `imagePullSecrets`. |
| `global.hooks.enabled` | bool | unset | Enables Helm hook annotations on chart-managed `ConfigMap` and `ExternalSecret` resources. |
| `global.hooks.weight` | string | `"-5"` | Hook weight emitted alongside `helm.sh/hook` annotations. |
| `global.hooks.preInstallEnvironments` | list | `[]` | Environments where ConfigMap / ExternalSecret resources are rendered as `pre-install,pre-upgrade` hooks. |
| `global.ingress.className` | string | unset | Default Ingress `spec.ingressClassName`. Per-component `<cmp>.ingress.className` overrides. |
| `global.ingress.annotations` | map | `{}` | Chart-wide Ingress annotations merged into every rendered Ingress. |
| `global.probe.<field>` | map | unset | Chart-wide probe field overrides. Slots between profile default and per-component value. See [Probes](#probes). |
| `global.envFrom.configs` / `.secrets` | list | unset | Chart-wide `envFrom` projections. See [`envFrom` shape and rails-profile phantom defaults](#envfrom-shape-and-rails-profile-phantom-defaults). |
| `global.securityContext.pod` | map | posture default | Chart-wide pod-level `securityContext` defaults merged over the `global.security` posture. |
| `global.securityContext.container` | map | posture default | Chart-wide container-level `securityContext` defaults merged over the `global.security` posture. |
| `global.prometheusEndpoint` | string | unset | Default `serverAddress` for KEDA `ScaledObject` Prometheus triggers. Required when any trigger has `type: prometheus` and no explicit `serverAddress`. |
| `global.monitoring.releaseLabel` | string | unset | When set, injects `release: <value>` onto every ServiceMonitor / PodMonitor / PrometheusRule so kube-prometheus-stack's default `release` selector discovers them (e.g. `kube-prometheus-stack`). |
| `global.pdb.minAvailable` | int\|string | unset | Fallback `minAvailable` for PodDisruptionBudgets, used when no per-component PDB bound is set and `global.pdb.maxUnavailable` is unset. Mutually exclusive with `maxUnavailable`. |
| `global.pdb.maxUnavailable` | int\|string | `25%` | Fallback `maxUnavailable` for PodDisruptionBudgets. PDB bound precedence: `<cmp>.pdb.minAvailable` > `<cmp>.pdb.maxUnavailable` > `global.pdb.minAvailable` > `global.pdb.maxUnavailable` > `25%`. |
| `global.secretStore` | string | unset | Chart-wide default `secretStoreRef.name` for ExternalSecrets. Per-secret `secrets.<name>.secretStore` overrides it. Required (here or per-secret) whenever `secrets` are defined, else the render fails. |
| `global.externalSecrets.apiVersion` | string | `external-secrets.io/v1` | ExternalSecret apiVersion. Set `external-secrets.io/v1beta1` for clusters running ESO < 0.14.0 (which do not serve `v1`). Validated against those two values. |
| `global.externalSecrets.forceSync` | bool | `true` | When `true` (default), stamps `force-sync: <now>` on every rendered `ExternalSecret`, so ESO re-reconciles on each `helm upgrade` — but this rewrites the annotation every render (GitOps diff noise). Set `false` for a stable per-revision value (`force-sync: <Release.Revision>`): noise-free diffs, reconcile only when the revision changes. |
| `global.deployment.replicasOnCreationAnnotation` | string | unset (`""`) | Annotation key for the "replicas at first install" hint. When `werf` annotations are enabled this falls back to `werf.io/replicas-on-creation`. Set to a non-empty string to opt in outside of werf. |
| `global.emitEnvironmentLabel` | bool | `true` | Emit `helm.sh/environment: <env>` label on all rendered resources. Set to `false` to opt out of this non-standard label. v3.0 will flip the default to `false`. |
| `global.compat.legacySelectorLabels` | bool | `false` | Use the pre-v2 selector label scheme for charts migrated from `werf`. |
| `global.werf.annotations` | bool | unset | Explicitly enable / disable werf-style annotation emission. |

## Public helpers

Utility templates a consumer chart may `include` directly. Stable public API (`common.*`).

| Helper | Signature (dict keys) | Notes / caveats |
|---|---|---|
| `common.indent` | `value`, `spaces` (default 2) | Indents every line after the first by `spaces`; first line is not indented. |
| `common.dbUrl` | `type` (default `postgres`), `host`, `port`, `name`, `user`, `password`, `options` | `user`/`password` are interpolated **verbatim, not URL-encoded** — pre-encode any value containing `@ : / ? #` (e.g. wrap with `urlquery`). Fails if `host`/`name` missing. |
| `common.formatUrl` | `protocol` (default `https`), `host`, `path` | Defaults to **https**; pass `protocol: "http"` to opt into insecure transport. Emits a leading newline — pipe through `trim`. Fails if `host` missing. |
| `common.generateName` | `prefix`, `separator` (default `-`), `length` (default 8) | **Non-deterministic** (uses `randAlphaNum`) — re-renders on every `helm upgrade`; do not use for stable resource names. |
| `generateName` | `name`, `suffix` (required) | **Deterministic** `<name>-<suffix>`, stable across renders — pass `.Release.Revision` for a per-revision name. Prefer this (not `common.generateName`) for Job/CronJob names that must not churn. |
| `common.format` | `value`, `type` (`yaml`\|`json`\|`raw`, default `yaml`) | Renders `value` in the chosen encoding. |
| `common.renderTemplateOrDefault` | `name`, `context`, `default` | Renders named template; falls back to `default` when the result trims empty. Emits a leading newline — pipe through `trim`. |
| `common.mergeValues` | `src`, `dest` | Wraps Sprig `merge $dest $src`: **dest-wins** — keys already present in `dest` are NOT overwritten by `src` (shallow-biased, not a true deep override merge). |
| `common.env.secretRef` | `name`, `secretName`, `key`, `optional` | Emits a single `valueFrom.secretKeyRef` env entry. |
| `common.env.configMapRef` | `name`, `configMapName`, `key`, `optional` | Emits a single `valueFrom.configMapKeyRef` env entry. |
| `common.env.fieldRef` | `name`, `fieldPath` | Emits a single `valueFrom.fieldRef` env entry. |

## Where things live in templates

| Concern | Template | Helper |
|---|---|---|
| Workload composition | `templates/_deployment.tpl`, `_statefulset.tpl`, `_daemonset.tpl`, `_job.tpl`, `_cronjob.tpl` | `templates/common/_workload.tpl` |
| Pod spec | (inside workloads) | `templates/common/_pod.tpl` |
| Container spec | (inside pod) | `templates/common/_container.tpl` |
| Labels/annotations/naming | (everywhere) | `templates/common/_general.tpl`, `_helpers.tpl` |
| Affinity / topology | (inside pod) | `templates/common/_affinities.tpl` |
| Language profile defaults | (inside container) | `templates/common/_profile.tpl` |
| Security posture defaults | (pod + container securityContext) | `templates/common/_profile.tpl` (`common.security`) |

> Include-API casing: prefer lowercase `chart.serviceaccount` / `chart.binaryconfigmap` (canonical, matching `chart.service` / `chart.configmap`). The camelCase `chart.serviceAccount` / `chart.binaryConfigmap` names are deprecated aliases retained for one minor.
