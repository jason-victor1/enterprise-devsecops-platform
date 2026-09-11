# Executive Architecture Summary: Enterprise Polyglot DevSecOps Platform

This reference architecture implements an end-to-end, zero-trust DevSecOps platform spanning seven polyglot microservices (Go, Python, Node.js, Ruby, Java, C#, PHP). The platform operationalizes a shift-left, fail-closed security model bridging source control governance, cryptographic software supply chain integrity, kernel-level runtime observability, and automated admission control.

---

### Core Security Control Matrix

| Architecture Domain | Security Controls & Tooling | Enforcement Point | Zero-Trust Objective |
| :--- | :--- | :--- | :--- |
| **Source & Branch Governance** | GitHub Rulesets, Push Protection, Linear History | Git Pre-receive / Remote Push | Prevents branch tampering and intercepts exposed credentials before entering commit history. |
| **Static Verification Gates (Phase 2)** | Gitleaks, Semgrep (AST), Checkov, Trivy | GitHub Actions CI Matrix | Fail-closed static analysis halting builds on high/critical CVEs, secret leaks, or insecure deserialization patterns. |
| **Supply Chain Integrity (Phase 3)** | Syft (CycloneDX 1.6), Sigstore / Cosign, Rekor Log | Post-Build / Registry Publication | Establishes cryptographic provenance using keyless OIDC identities and generates verifiable SBOM attestations. |
| **Cluster Admission Control** | Kyverno ValidatingWebhook | Kubernetes API Server | Restricts workload deployment strictly to cryptographically verified, Cosign-signed images matching Rekor logs. |
| **Network Microsegmentation** | Cilium (eBPF) L3/L4/L7 Policies | Kernel / Socket Layer | Enforces default-deny isolation; explicitly authorizes only declared ingress/egress service flows. |
| **Dynamic Secrets Delivery** | HashiCorp Vault Agent, Kubernetes Auth | In-Memory `tmpfs` Volume | Completely eliminates long-lived secrets and environment variables via auto-rotating, ephemeral tokens. |
| **Runtime Threat Defense** | Falco (Modern eBPF Engine) | Linux Kernel Syscall Interface | Real-time behavioral detection intercepting abnormal runtime activities (e.g., unauthorized `execve` shells). |

---

### Architecture Pillars

#### 1. Software Supply Chain & Cryptographic Provenance
* **Keyless Signing via OpenID Connect:** Build artifacts do not rely on static private keys. Workloads obtain ephemeral X.509 certificates from Fulcio through GitHub Actions OIDC identity tokens, binding container images directly to the workflow file and Git ref.
* **Immutable Transparency Ledger:** Cryptographic proofs and transparency hashes are recorded directly in Sigstore's Rekor log, ensuring non-repudiation and offline verification.
* **Machine-Readable SBOMs:** Syft automatically generates CycloneDX 1.6 software bills of materials attached as in-toto attestations directly to container digests on GitHub Container Registry (GHCR).

#### 2. Shift-Left CI/CD Gateways
* **Fail-Closed Static Analysis:** The Phase 2 pipeline runs parallel security linters across code, dependencies, and infrastructure manifests. Any breach of security thresholds immediately exits code 1, aborting downstream build triggers.
* **Context-Aware Secrets Auditing:** Gitleaks scans commit diffs while respecting strict, deterministic allowlists for synthetic test fixtures and unit tests.
* **Dependency Health:** Automated Dependabot patching ensures immediate remediation of known vulnerabilities, keeping repository technical debt at zero open alerts.

#### 3. Infrastructure Admission & Microsegmentation
* **Cryptographic Admission Verification:** Kyverno intercepts workload deployment manifests at cluster ingress. Unsigned container images or artifacts missing valid Cosign attestations fail-closed before scheduling onto worker nodes.
* **Kernel-Level Zero-Trust Networking:** Cilium replaces traditional `iptables` with an eBPF data path. Lateral service communication is explicitly blocked unless defined by fine-grained `CiliumNetworkPolicy` resources.

#### 4. Ephemeral Secrets & Runtime Detection
* **Zero Disk / Zero Env Leakage:** Pods consume database credentials, API keys, and mutual TLS certificates delivered by HashiCorp Vault Agent directly into in-memory `tmpfs` mounts.
* **Kernel-Level Intrusion Interception:** Falco’s modern eBPF probe monitors cluster syscall streams. Any interactive container breakout or unexpected process spawn triggers instant alerts without adding user-space monitoring latency.

---

### Adversarial Verification Summary

The reference architecture was empirically validated against six automated adversarial test drills simulating real-world attack vectors:

1. **Drill 01 (Static Secrets Ingestion):** Blocked at pre-commit and CI via Gitleaks rules.
2. **Drill 02 (Insecure AST Deserialization):** Flagged and halted during Semgrep code analysis.
3. **Drill 03 (Unsigned Image Tampering):** Denied deployment by Kyverno admission webhooks.
4. **Drill 04 (Lateral East-West Reconnaissance):** Dropped at the eBPF layer by Cilium default-deny policies.
5. **Drill 05 (In-Memory Secret Exfiltration):** Mitigated by Vault Agent non-persistent memory boundaries.
6. **Drill 06 (Container Shell Execution):** Detected instantly via Falco `execve` syscall rules.

Formal execution evidence and raw cryptographic logs are cataloged in [`docs/verification-evidence.md`](./verification-evidence.md).
