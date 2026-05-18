## Summary

<!-- One sentence: what does this PR change and why? -->

## Type

<!-- Mark one: -->
- [ ] `fix` — bug fix (no behaviour change beyond the bug)
- [ ] `feat` — new feature or template
- [ ] `docs` — documentation only
- [ ] `refactor` — code change with no behaviour change (golden-stable)
- [ ] `ci` — CI / tooling change
- [ ] `BREAKING` (`!` suffix in commit subject) — backwards-incompatible change

## Linked issue

<!-- "Closes #123" or "Refs #123" — delete if not applicable. -->

## Pre-merge checklist

- [ ] `make lint && make golden-check` is green locally
- [ ] If goldens drifted, the diff matches the intent and the commit body explains it
- [ ] If introducing a new feature, an `examples/values.<feature>.yaml` fixture is added
- [ ] If backwards-incompatible, the change is recorded in `docs/migration-v1-to-v2.md` (or its successor `docs/migration-v2-to-v3.md` etc.)
- [ ] Commit messages follow conventional-commit subjects (`fix(scope):`, `feat(scope):`, breaking marker `!`)
- [ ] No commits under `docs/superpowers/`, `CLAUDE.md`, `RTK.md`, `AGENTS.md` (locally `.gitignore`d files)

## Notes for reviewer

<!-- Anything non-obvious about the change. Trade-offs you considered. Things you considered but deliberately didn't do. -->
