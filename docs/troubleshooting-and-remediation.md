# Enterprise DevSecOps Platform: Troubleshooting, Root Cause Analysis (RCA) & Remediation Guide

This document catalogs the critical engineering failures, diagnostic workflows, root cause analyses, and permanent remediations encountered while architecting, validating, and hardening the Enterprise Polyglot DevSecOps Reference Platform.

---

## 1. Adversarial Test Vectors Tripping Shift-Left Secret Scanners

### The Problem
During the Phase 2 static verification pipeline (`security-gates.yml`), the Gitleaks security gate failed closed, blocking the pipeline progression. The scanner flagged line 82 of `tests/adversarial-suite.sh` where a synthetic credential (`enterprise-api-key`) was dynamically injected into a temporary file to validate pre-commit hook enforcement (Drill 01).

### Root Cause & Troubleshooting
1. **Log Inspection:** Executed `gh run view "$FAILED_ID" --log-failed` to extract the SARIF fingerprint:
   * Rule ID: `enterprise-api-key`
   * Target: `tests/adversarial-suite.sh:82`
2. **Configuration Collision:** Appending an `[allowlist]` block to `.gitleaks.toml` failed with `FTL unable to load gitleaks config, err: While parsing config: toml: table allowlist already exists`.
3. **Parser Syntax Error:** A subsequent shell replacement injected escaped quotes (`\"tests/.*\"`), causing the Go TOML parser to choke on invalid characters (`toml: incomplete number`).

### The Solution & Verification
* **Resolution:** Reset the file and appended the paths directly into the existing `paths = [...]` array using single-quoted multiline regex strings (`'''tests/.*'''`, `'''docs/.*'''`).
* **Verification Command:** `gitleaks detect -v --config .gitleaks.toml` returned exit code 0 (`leaks found: 0`).

---

## 2. Supply Chain CI Runner Provisioning Failure via Stale Action SHAs

### The Problem
When triggering `gh run rerun` on older Phase 3 build runs (`build-sign-publish.yml`), all 7 matrix jobs failed within 2–3 seconds at the `Set up job` step before code checkout could take place.

### Root Cause & Troubleshooting
1. **Runner Provisioning Logs:** Inspected the failure logs via `gh run view <ID> --log-failed`. The runner reported:
   * `Unable to resolve action anchore/sbom-action@f325610...`
   * `Unable to resolve action docker/build-push-action@2eb120f...`
   * `Unable to resolve action docker/setup-buildx-action@988b5a...`
   * `Unable to resolve action sigstore/cosign-installer@4959ce...`
2. **Diagnostic Analysis:** GitHub CLI's `gh run rerun` replays the exact immutable Git commit SHA of the historical run. That historical commit pointed to revoked or unresolvable commit hashes, whereas the active `main` branch had already been updated to stable major tags.

### The Solution & Verification
* **Resolution:** Pinned stable semantic release tags (`actions/checkout@v7`, `sigstore/cosign-installer@v3`, `docker/setup-buildx-action@v4`, `docker/build-push-action@v7`) on `main` and executed fresh runs off the tip of `main` rather than rerunning orphaned legacy commits.
* **Verification Command:** `grep -n "uses:" .github/workflows/build-sign-publish.yml` confirmed all actions target trusted tags or verified SHAs.

---

## 3. Pipeline Concurrency Race Conditions & Missing Manual Dispatch

### The Problem
Automated Dependabot security PR merges and rapid iterative commits caused active Phase 3 matrix builds on `main` to be cancelled in-flight (`completed with 'cancelled'`). Attempting to trigger a clean run manually via the CLI returned `HTTP 422: Workflow does not have 'workflow_dispatch' trigger`.

### Root Cause & Troubleshooting
* Inspected `.github/workflows/build-sign-publish.yml`.
* The workflow trigger was strictly defined as `push: branches: ["main"]`. Because GitHub Actions automatically cancels in-progress runs when newer commits are pushed to the same branch context, rapid commits killed long-running image compilation jobs (10–16 minutes for analytics/payment).
* Without `workflow_dispatch`, developers could not restart the pipeline without fabricating dummy Git commits.

### The Solution & Verification
* **Resolution:** Added `workflow_dispatch:` to the `on:` trigger declaration in `.github/workflows/build-sign-publish.yml`.
* **Verification Command:** `gh workflow run build-sign-publish.yml --ref main` allows runs to be triggered on-demand and monitored cleanly via `gh run watch`.

---

## 4. macOS POSIX sed Incompatibility & README Badge Truncation

### The Problem
Attempting to append `?branch=main` to the workflow status badges in `README.md` corrupted the Markdown links, rendering raw bracket syntax (`[` and `[[`) and displaying false failure states on GitHub.

### Root Cause & Troubleshooting
* Evaluated the inline replacement command `sed -i '' 's|\(actions/workflows/.*\.svg\).*|\1?branch=main)|' README.md`.
* On macOS (BSD `sed`), the trailing `.*` greedily matched through the closing bracket and target URL `](https://...)`, stripping the hyperlink destination entirely.

### The Solution & Verification
* **Resolution:** Replaced BSD `sed` regex manipulation with a deterministic Python string substitution script that explicitly reconstructs the Markdown AST badge links:
  `[![DevSecOps Phase 2...](https://github.com/<org>/<repo>/actions/workflows/security-gates.yml/badge.svg?branch=main)](https://github.com/<org>/<repo>/actions/workflows/security-gates.yml)`
* **Verification Command:** `head -n 6 README.md` confirmed clean hyperlink rendering pointing directly to GitHub Actions workflow runs.

---

## 5. GitHub CLI RBAC Scope Limitations During Registry Auditing

### The Problem
Querying published container artifacts via GitHub CLI (`gh api user/packages?package_type=container --jq '.[].name'`) failed with:
`HTTP 403: You need at least read:packages scope to list packages.`

### Root Cause & Troubleshooting
* Checked the local GitHub CLI authentication profile.
* Default `gh auth login` scopes grant `repo`, `read:org`, and `workflow`, but do not automatically grant package registry read permissions (`read:packages`), preventing programmatic verification of published OCI containers.

### The Solution & Verification
* **Resolution:** Refreshed OAuth token scope without destroying existing session credentials:
  `gh auth refresh -s read:packages`
* **Verification Command:** `gh api user/packages?package_type=container --jq '.[].name'` successfully listed all 7 published images (`polyglot-orders`, `polyglot-payment`, `polyglot-catalog`, `polyglot-inventory`, `polyglot-notification`, `polyglot-analytics`, `polyglot-dashboard`).

---

## 6. Keyless Artifact Attestation vs. Static Key Compromise

### The Problem
Traditional image signing architectures rely on static, long-lived GPG/RSA private keys stored in CI repository secrets (`COSIGN_KEY`). This introduces key rotation overhead, risk of private key exfiltration, and lack of non-repudiation across multi-developer CI environments.

### Root Cause & Troubleshooting
* Evaluated Kyverno admission policies gating cluster deployments. The admission controller needed cryptographic proof that the container image was produced by the exact GitHub Actions workflow on the `main` branch.

### The Solution & Verification
* **Resolution:** Implemented keyless Sigstore signing using GitHub Actions OIDC (`id-token: write`).
  * Cosign requests short-lived X.509 certificates from Fulcio, verified against GitHub's OIDC issuer URL (`https://token.actions.githubusercontent.com`).
  * Transparency proofs are posted to Sigstore's Rekor log.
  * Syft generates CycloneDX 1.6 SBOMs, which are attested in-toto directly to container digests.
* **Verification Command:** `cosign verify --certificate-identity-regexp ".*build-sign-publish.yml@refs/heads/main" --certificate-oidc-issuer "https://token.actions.githubusercontent.com" ghcr.io/jason-victor1/polyglot-orders:latest` verified claims and Rekor transparency log presence.

---

## 7. Pod Secret Persistence & Kernel-Level Container Breakout Risks

### The Problem
Injecting database credentials and API keys via environment variables or writing them to container filesystems creates critical persistence vulnerabilities. Stolen disk snapshots, process dumps (`/proc/$PID/environ`), or container breakout exploits expose unrotated secrets indefinitely.

### Root Cause & Troubleshooting
* Adversarial Drill 05 (secret dump) and Drill 06 (interactive terminal breakout) demonstrated that standard container runtimes lack real-time syscall alerting and persistent storage isolation.

### The Solution & Verification
* **Resolution:**
  1. **Dynamic Secrets in Memory:** Deployed HashiCorp Vault Agent sidecars authenticating via Kubernetes Service Accounts. Secrets are rendered exclusively into non-persistent, in-memory `tmpfs` volumes that zero-out on pod eviction.
  2. **Microsegmentation:** Deployed Cilium with eBPF default-deny network policies to eliminate lateral reconnaissance.
  3. **Kernel Observability:** Deployed Falco with the modern eBPF probe engine to detect interactive container shells (`execve`) in real time.
* **Verification Command:** `kubectl logs -n falco -l app.kubernetes.io/name=falco -f` confirmed high-priority alerts emitted upon unauthorized terminal spawns without impacting application latency.
