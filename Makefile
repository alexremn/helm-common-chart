SHELL := $(shell command -v zsh 2>/dev/null || command -v bash 2>/dev/null || command -v sh 2>/dev/null || printf '%s\n' /bin/sh)

HELM ?= helm
SMOKE_DIR ?= tests/smoke
GOLDEN_DIR ?= tests/golden
CANARYBOT_CHART ?= ../../../bots/canarybot/.helm
TMP_CANARYBOT ?= /tmp/canarybot-common-compat

.PHONY: lint lint-library lint-smoke render-smoke golden-update golden-check lint-canarybot-compat \
        validate validate-kubeconform validate-kube-linter

# Phase C1 — validation tooling.
KUBECONFORM_VERSION ?= v0.7.0
KUBE_LINTER_VERSION ?= v0.8.3
K8S_VERSIONS ?= 1.24.0 1.28.0 1.31.0

lint: lint-library lint-smoke

lint-library:
	$(HELM) lint .

SMOKE_VARIANTS := generic werf-legacy image-resolution features profile-generic profile-rails profile-python profile-go \
                  mixed-profiles \
                  daemonset hpa vpa networkpolicy networkpolicy-egress secret rbac servicemonitor \
                  prometheusrule priorityclass triggerauth automount \
                  automount-pod-default securitycontext security-decoupled sa-not-created \
                  job-podannotations pdb-podmonitor-pvc-sa-annotations \
                  tpl-scoping ingress-no-tls extsecret-namespaced \
                  no-environment-label

# Lint the smoke chart and render every value set. Used by CI.
lint-smoke:
	( cd $(SMOKE_DIR) && \
	trap 'rm -f Chart.lock charts/common-*.tgz; rmdir charts 2>/dev/null || true' EXIT && \
	$(HELM) dependency build --skip-refresh >/tmp/common-smoke-deps.log && \
	for variant in $(SMOKE_VARIANTS); do \
	  $(HELM) lint . -f values-$$variant.yaml || exit $$?; \
	  $(HELM) template smoke . -f values-$$variant.yaml >/tmp/common-smoke-$$variant.out || exit $$?; \
	done )

# Render outputs without linting (faster for iterating).
# Normalizes `force-sync: <timestamp>` to a fixed string so golden diffs are stable.
render-smoke:
	( cd $(SMOKE_DIR) && \
	trap 'rm -f Chart.lock charts/common-*.tgz; rmdir charts 2>/dev/null || true' EXIT && \
	$(HELM) dependency build --skip-refresh >/tmp/common-smoke-deps.log && \
	for variant in $(SMOKE_VARIANTS); do \
	  $(HELM) template smoke . -f values-$$variant.yaml \
	    | sed -E 's/force-sync: ".*"/force-sync: "<NOW>"/' \
	    >/tmp/common-smoke-$$variant.out || exit $$?; \
	done )

# Refresh the golden references after an intentional change.
golden-update: render-smoke
	mkdir -p $(GOLDEN_DIR)
	@for variant in $(SMOKE_VARIANTS); do \
	  cp /tmp/common-smoke-$$variant.out $(GOLDEN_DIR)/baseline-$$variant.out; \
	done
	@echo "Golden files updated. Review the diff with 'git diff $(GOLDEN_DIR)' before committing."

# Compare current renders against golden references. Fails on any drift.
# Used by CI to gate accidental template behavior changes.
golden-check: render-smoke
	@rc=0; \
	for variant in $(SMOKE_VARIANTS); do \
	  if ! diff -u $(GOLDEN_DIR)/baseline-$$variant.out /tmp/common-smoke-$$variant.out; then \
	    echo "FAIL: $$variant render does not match golden. Run 'make golden-update' if intentional." >&2; \
	    rc=1; \
	  fi; \
	done; \
	exit $$rc

lint-canarybot-compat:
	@if [ -d "$(CANARYBOT_CHART)" ]; then \
	  rm -rf "$(TMP_CANARYBOT)" && \
	  mkdir -p "$(TMP_CANARYBOT)" && \
	  cp -R "$(CANARYBOT_CHART)"/* "$(TMP_CANARYBOT)"/ && \
	  rm -rf "$(TMP_CANARYBOT)/charts/common" "$(TMP_CANARYBOT)/charts/common-1.1.4.tgz" && \
	  cp -R . "$(TMP_CANARYBOT)/charts/common" && \
	  printf '%s\n' \
	    'apiVersion: v2' \
	    'name: canarybot' \
	    'version: 0.0.0' \
	    'dependencies:' \
	    '  - name: common' \
	    '    version: "^1.0.0"' \
	    '    repository: "file://charts/common"' > "$(TMP_CANARYBOT)/Chart.yaml" && \
	  cd "$(TMP_CANARYBOT)" && \
	  $(HELM) lint . -f values.yaml -f envs/common.yaml -f envs/dev.yaml --set werf.name=canarybot,werf.env=dev,werf.image.app=ghcr.io/example/canarybot:dev && \
	  $(HELM) lint . -f values.yaml -f envs/common.yaml -f envs/prod.yaml --set werf.name=canarybot,werf.env=production,werf.image.app=ghcr.io/example/canarybot:prod && \
	  $(HELM) template canarybot . -f values.yaml -f envs/common.yaml -f envs/dev.yaml --set werf.name=canarybot,werf.env=dev,werf.image.app=ghcr.io/example/canarybot:dev >/tmp/canarybot-dev-render.out && \
	  $(HELM) template canarybot . -f values.yaml -f envs/common.yaml -f envs/prod.yaml --set werf.name=canarybot,werf.env=production,werf.image.app=ghcr.io/example/canarybot:prod >/tmp/canarybot-prod-render.out; \
	else \
	  echo "Skip canarybot compatibility check: $(CANARYBOT_CHART) not found"; \
	fi

# Run all validation gates. Assumes /tmp/common-smoke-*.out exists from render-smoke.
validate: render-smoke validate-kubeconform validate-kube-linter

# kubeconform schema validation against multiple k8s versions.
# Files are fed via stdin because kubeconform only auto-detects .yaml/.json extensions.
validate-kubeconform:
	@set -e; \
	for variant in $(SMOKE_VARIANTS); do \
	  for ver in $(K8S_VERSIONS); do \
	    kubeconform -strict -ignore-missing-schemas -summary -verbose \
	      -schema-location default \
	      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/5f127a5ac3655e83d40f7ad8d4b7392c89e36b38/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json' \
	      -kubernetes-version $$ver \
	      - < /tmp/common-smoke-$$variant.out \
	      || { echo "FAIL kubeconform: $$variant @ k8s $$ver" >&2; exit 1; }; \
	  done; \
	done

# kube-linter anti-pattern detection.
validate-kube-linter:
	@set -e; \
	for variant in $(SMOKE_VARIANTS); do \
	  kube-linter lint /tmp/common-smoke-$$variant.out --config .kube-linter.yaml \
	    || { echo "FAIL kube-linter: $$variant" >&2; exit 1; }; \
	done
