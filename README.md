# helm-common-chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/helm-common-chart)](https://artifacthub.io/packages/search?repo=helm-common-chart)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
![Helm](https://img.shields.io/badge/Helm-%5E4.x-0F1689)
![Kubernetes](https://img.shields.io/badge/Kubernetes-%3E%3D1.24-326CE5)
[![Cosign verified](https://img.shields.io/badge/Cosign-keyless%20verified-darkgreen)](./SECURITY.md#verification)

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

Minimal `values.yaml` for a consumer chart that depends on `common`:

```yaml
name: my-app
environment: dev

web:
  replicas: 2
  image:
    repository: ghcr.io/example/my-app
    tag: "1.0.0"
  ports:
    http: 8080
```

And in your chart's `templates/all.yaml`:

```yaml
{{ include "chart.deployment" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
---
{{ include "chart.service" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
```

Each per-resource template is invoked the same way — pass a `dict` carrying the root `Values`/`Release`/`Chart` plus a `cmp` key naming the component subtree to render (here, `web`). Available entrypoints include `chart.deployment`, `chart.statefulset`, `chart.daemonset`, `chart.job`, `chart.cronjob`, `chart.service`, `chart.service.headless`, `chart.ingress`, `chart.networkpolicy`, `chart.configmap`, `chart.binaryconfigmap`, `chart.secret`, `chart.extsecret`, `chart.serviceaccount`, `chart.rbac`, `chart.hpa`, `chart.vpa`, `chart.scaledobject`, `chart.triggerauth`, `chart.pdb`, `chart.pvc`, `chart.podmonitor`, `chart.servicemonitor`, `chart.prometheusrule`, `chart.priorityclass`.

See [`tests/smoke/templates/all.yaml`](./tests/smoke/templates/all.yaml) for a complete consumer-side template wiring multiple resources, and [`examples/`](./examples/) for richer fixtures (HPA, VPA, NetworkPolicy, ServiceMonitor, profiles, etc.).

## What's inside

Workloads: Deployment, StatefulSet, DaemonSet, Job, CronJob
Networking: Service, Ingress, NetworkPolicy
Scaling: HPA, VPA, KEDA ScaledObject + TriggerAuthentication, PodDisruptionBudget
Observability: ServiceMonitor, PodMonitor, PrometheusRule
Config & Secrets: ConfigMap, Secret, ExternalSecret
RBAC: ServiceAccount, Role, RoleBinding
Storage: PersistentVolumeClaim
Misc: PriorityClass

Common helper library (`templates/common/`): workload composition, container building, pod spec, profile defaults, affinity/topology helpers, naming. See [Public helpers](./docs/values-reference.md#public-helpers) for the consumer-facing `common.*` utility API.

## Docs

- [Values reference](./docs/values-reference.md) — top-level keys grouped by concern
- [Examples](./examples/) — working `values.*.yaml` per feature
- [Contributing](./CONTRIBUTING.md) — dev setup, tests, golden workflow
- `values.schema.json` — full JSON schema (validated by `helm lint`)

## License

Apache-2.0. See [LICENSE](./LICENSE).
