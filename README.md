# helm-common-chart

Library Helm chart providing reusable templates for Kubernetes workloads, services, autoscaling, and observability.

## What this is

A **library chart** (`type: library`) — it is not installable standalone. Consume it as a dependency from your application chart and call its helpers and template definitions from your own templates.

## Install

Releases are published as OCI artifacts on GitHub Container Registry. In your application chart's `Chart.yaml`, add:

```yaml
dependencies:
  - name: common
    version: "^2.0.0"
    repository: "oci://ghcr.io/alexremn/charts"
```

Then:

```bash
helm dependency update
```

To pull the chart directly:

```bash
helm pull oci://ghcr.io/alexremn/charts/common --version 2.0.0
```

## Quick start

Minimal `values.yaml` that renders a Deployment + Service via the library:

```yaml
name: my-app
environment: dev

app:
  replicas: 2
  image:
    repository: ghcr.io/example/my-app
    tag: "1.0.0"
  ports:
    http: 8080
  service:
    type: ClusterIP
    ports:
      http: 80
```

And in your chart's `templates/deployment.yaml`:

```yaml
{{ include "common.workload" (dict "context" . "name" "app") }}
```

See [`examples/`](./examples/) for richer fixtures (HPA, VPA, NetworkPolicy, ServiceMonitor, profiles, etc.).

## What's inside

Workloads: Deployment, StatefulSet, DaemonSet, Job, CronJob
Networking: Service, Ingress, NetworkPolicy
Scaling: HPA, VPA, KEDA ScaledObject + TriggerAuthentication, PodDisruptionBudget
Observability: ServiceMonitor, PodMonitor, PrometheusRule
Config & Secrets: ConfigMap, Secret, ExternalSecret
RBAC: ServiceAccount, Role, RoleBinding
Storage: PersistentVolumeClaim
Misc: PriorityClass

Common helper library (`templates/common/`): workload composition, container building, pod spec, profile defaults, affinity/topology helpers, naming.

## Docs

- [Values reference](./docs/values-reference.md) — top-level keys grouped by concern
- [Migrating v1 → v2](./docs/migration-v1-to-v2.md) — required input changes and breaking-default audit
- [Examples](./examples/) — working `values.*.yaml` per feature
- [Contributing](./CONTRIBUTING.md) — dev setup, tests, golden workflow
- `values.schema.json` — full JSON schema (validated by `helm lint`)

## License

Apache-2.0. See [LICENSE](./LICENSE).
