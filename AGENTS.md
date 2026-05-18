# AGENTS.md

This file is read by AI coding assistants (Claude Code, Cursor, etc.) before they
make changes in this repo. Keep it under ~80 lines.

## What this is

A Helm v4 library chart (`Chart.yaml` `type: library`) providing reusable
templates for Kubernetes workloads, services, autoscaling, observability,
RBAC, configs/secrets, and storage. Library charts emit no resources of their
own; they expose `common.*` helpers and template definitions consumed by
application charts via the `dependencies` mechanism.

## Layout

- `templates/` — top-level resource templates (one per kind: deployment,
  service, ingress, etc.) and `templates/common/` helper library.
- `tests/smoke/` — `values-<variant>.yaml` fixtures rendered by the smoke
  harness. Add a new variant to `Makefile`'s `SMOKE_VARIANTS` when introducing
  a feature that needs golden coverage.
- `tests/golden/baseline-<variant>.out` — committed renders for each smoke
  variant. CI gate via `make golden-check`.
- `examples/` — user-facing values samples (one per feature). Not exercised by
  CI directly; serves as docs.
- `docs/values-reference.md` — top-level values schema reference.
- `docs/migration-v1-to-v2.md` — v1 → v2 upgrade guide.

## Build / test

```
make lint           # helm lint on library + every smoke variant
make golden-check   # diff renders against committed golden; CI gate
make golden-update  # regenerate goldens after intentional change
```

A normal pre-PR check is `make lint && make golden-check`.

## Adding a new template kind

See `CONTRIBUTING.md` § "Adding a new template kind". Summary: create
`templates/_<kind>.tpl`, reuse helpers from `templates/common/`, add a
fixture in `examples/` + a smoke variant in `tests/smoke/`, run
`make golden-update`, commit.

## Conventions

- Library helpers are namespaced by file: `_workload.tpl` → `common.workload.*`,
  `_pod.tpl` → `common.pod.*`, etc.
- Keep helpers small and single-purpose; split if past ~30 lines.
- Behaviour-changing PRs include a regenerated golden + a commit-body
  explanation of the diff.
- Public-release blockers tracked in `docs/migration-v1-to-v2.md`.

## Out of scope for AI changes

- Application-specific business logic (this is a library, not a per-app chart).
- Auto-regenerating goldens during code review (always inspect the diff).
- Adding runtime dependencies (this chart has zero by design).
- Editing files matched by `.gitignore` (`CLAUDE.md`, `RTK.md`, `docs/superpowers/`).
