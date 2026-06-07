# Security Policy

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Use GitHub's private security-advisory flow:
<https://github.com/alexremn/helm-common-chart/security/advisories/new>

Or email the maintainers: `alexander@remniov.com`.

You will receive an acknowledgement within **5 business days**. Coordinated
disclosure timelines are negotiated per report — typically 30 to 90 days
between acknowledgement and public disclosure depending on severity and
mitigation availability.

## Supported Versions

| Version | Supported               |
|---------|-------------------------|
| 2.x     | :white_check_mark:      |
| 1.x     | :x: (pre-public)        |

Only the latest minor release line receives security fixes. Pin
`version: "^2.0.0"` (or a tighter constraint) in your application chart's
`dependencies` to opt into ongoing fixes.

## Scope

This is a Helm **library chart**. It emits no Kubernetes resources of its own;
its templates render manifests on behalf of consumer charts. The following
issues are in scope for this policy:

- Unsafe defaults that grant excessive permissions (RBAC, ServiceAccount
  auto-mount, NetworkPolicy egress) without explicit caller opt-in.
- Render-time code execution beyond the documented `tpl` surface in
  `common.envs` (see the SECURITY paragraph in that helper's docstring).
- Credential or secret leakage through emitted manifests (annotations,
  envFrom phantoms, ConfigMap embedding of sensitive values).
- Template logic that produces malformed manifests rejected at admission
  but accepted by `helm template` (silent-failure paths).
- Supply-chain integrity of the published OCI artifact at
  `ghcr.io/alexremn/charts/common`.

The following are **out of scope** for security reports (open a regular issue
instead):

- Application-level vulnerabilities in workloads deployed via this chart —
  those belong to the consumer chart or the application image.
- Misconfiguration on the consumer side (`global.profile`,
  `serviceAccount.name`, etc.) that opens a permission their own values
  requested.

## Hardening recommendations for consumers

- Set `global.security: generic` to enable the hardened container
  `securityContext` (`runAsNonRoot`, `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem`, `capabilities.drop: [ALL]`). The default posture is
  `minimal` (no enforced container hardening) — profiles no longer imply a
  securityContext.
- Pin chart version: `version: "2.0.x"` (drop `^` to fully pin a patch).
- Verify OCI artifact digest in CI: `helm pull oci://ghcr.io/alexremn/charts/common --version <ver>` and compare to the digest published on the GitHub Release page.
- Override `serviceAccount.automount: true` explicitly only for workloads
  that call the Kubernetes API. The library default is `false` since v2.0.0.
- Set `secrets.<name>.secretStore` and `scaledObject.triggers[].metadata.serverAddress` explicitly — both are required (no default) since v2.0.0.

## Verification

Every tagged release is signed with [Sigstore Cosign](https://www.sigstore.dev/)
via GitHub Actions OIDC (keyless — no long-lived signing keys). Verify
before installing:

```
cosign verify \
  --certificate-identity-regexp "^https://github.com/alexremn/helm-common-chart/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/alexremn/charts/common:<version>
```

A successful verification confirms:
- The OCI artifact was signed by a GitHub Actions workflow run in this repository.
- The signature is recorded in the Sigstore public transparency log (Rekor).
- The image digest has not been altered since signing.

### SBOM

Each release ships SBOMs in two formats:

- `common-v<version>.spdx.json` — SPDX 2.3 format
- `common-v<version>.cdx.json` — CycloneDX 1.5 format

Both are attached to the GitHub Release page. Download them alongside the
chart `.tgz` to inspect the file inventory and licensing.

### Tooling

Install `cosign` from <https://github.com/sigstore/cosign/releases>.
Install `syft` from <https://github.com/anchore/syft/releases> if you
want to regenerate SBOMs locally.
