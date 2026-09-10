# Contributing to the Enterprise DevSecOps Reference Platform

All submissions must adhere to the zero-trust architecture and defense-in-depth principles implemented across this repository.

## Local Prerequisites

* **Docker Engine** (or Docker Desktop)
* **Kind** (`v0.22+`) & **Kubectl** (`v1.28+`)
* **Helm** (`v3.14+`)
* **Cosign** (`v2.2+`)
* **Gitleaks** (`v8.18+`)
* **Semgrep** (`v1.70+`)

## Verification Workflow

1. **Branch Hygiene**: Create feature branches off `main` (`feat/workload-hardening` or `fix/network-policy`).
2. **Static Scans**:
```bash
gitleaks detect --config=.gitleaks.toml --verbose
semgrep scan --config=.semgrep/rules.yml services/
```
3. **Adversarial Regression Test Harness**:
Execute the automated 6-drill suite against a running cluster before opening a PR:
```bash
./tests/adversarial-suite.sh
```
4. **Commit Structure**: Use Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:`).
