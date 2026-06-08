# Contributing

Thanks for considering a contribution. This chart is a public OSS library; PRs and issues are welcome.

## Dev setup

Required:
- Helm v4 (`helm version` should report `v4.x`)
- `make`
- A Bourne-compatible shell (Makefile auto-detects `zsh`, `bash`, or `sh`)

Optional:
- `jq` or Python 3 for `values.schema.json` validation

## Running tests

The Makefile drives all checks.

```bash
make lint           # helm lint on library + all smoke variants
make render-smoke   # helm template every smoke variant to /tmp
make golden-check   # diff renders against committed golden files (CI gate)
```

A normal pre-PR check is `make lint && make golden-check`.

## Golden workflow

`tests/golden/baseline-<variant>.out` is the committed render of `tests/smoke/values-<variant>.yaml`.

When you make an **intentional** template or fixture change that affects output:

```bash
make golden-update
git diff tests/golden    # REVIEW every line — does it match the intent?
git add tests/golden
```

If `git diff` shows anything unexpected, your change has a side-effect you didn't realize. Investigate before committing.

`make golden-check` runs in CI; any drift fails the build.

## Adding a new template kind

1. Create `templates/_<kind>.tpl` defining the public entrypoint `chart.<kind>` (follow patterns in existing templates, e.g. `templates/_deployment.tpl`, which defines `chart.deployment`). Public entrypoints consumers `include` are `chart.*`; the `common.*` definitions under `templates/common/` are internal helpers.
2. Use shared helpers from `templates/common/` (`_workload.tpl`, `_pod.tpl`, `_container.tpl`, `_general.tpl`, `_helpers.tpl`).
3. Add a feature fixture in `examples/values.<kind>.yaml` for users.
4. Add a smoke fixture in `tests/smoke/values-<kind>.yaml`.
5. Add `<kind>` to `SMOKE_VARIANTS` in `Makefile`.
6. Run `make golden-update` to record the baseline; commit it.
7. Open a PR — CI runs `make lint` and `make golden-check`.

## Helper conventions

Helpers live under `templates/common/` and are namespaced by file:
- `_workload.tpl` — `common.workload` and friends
- `_pod.tpl` — `common.pod.*`
- `_container.tpl` — `common.container.*`
- `_general.tpl` — labels, annotations, naming
- `_helpers.tpl` — leaf utilities
- `_affinities.tpl` — affinity/topology helpers
- `_profile.tpl` — language/runtime profile defaults

Keep helpers small and single-purpose. If a helper grows past ~30 lines, consider splitting.

## PR rules

- `make lint && make golden-check` must pass
- New features add an `examples/values.<feature>.yaml` fixture
- Behavior-changing PRs include a regenerated golden + a brief diff explanation in the PR body
- Keep commits focused; prefer multiple small commits over one large one

## License

By contributing you agree your changes are licensed under Apache-2.0 (see `LICENSE`).
