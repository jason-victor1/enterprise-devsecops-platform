# DevSecOps Platform Verification Evidence & Attestation Record

**Target Cluster:** Kind (`devsecops-cluster`)  
**Commit SHA:** `adcdd7a64649e22010952066f5f4a4acfd8c0447`  
**CI Workflow:** DevSecOps Phase 3: Build, Sign, and Publish Artifacts  
**Registry:** GitHub Container Registry (`ghcr.io/jason-victor1/*`)  

---

## 1. Automated Verification Scorecard (Adversarial Suite)

The adversarial test suite (`tests/adversarial-suite.sh`) validates security boundaries across build-time, admission, and runtime control planes. All six layers operate in **fail-closed** mode:

| ID | Attack Vector / Test Case | Defensive Layer Tested | Verification Status | Gate Mode |
|:---|:---|:---|:---|:---|
| **01** | Secret Commit Leak | Gitleaks Pre-Commit Hook | **PASSED** (Blocked) | Fail-Closed (Static Hook) |
| **02** | Insecure Deserialization | Semgrep Polyglot SAST | **PASSED** (Blocked) | Fail-Closed (CI Gate) |
| **03** | Unsigned Image Deploy | Kyverno Admission Controller | **PASSED** (Blocked) | Fail-Closed (Webhook) |
| **04** | Lateral Network Probing | Cilium NetworkPolicy (eBPF) | **PASSED** (Blocked) | Fail-Closed (Network CNI) |
| **05** | Dynamic Secret Leakage | Vault Agent Sidecar (`tmpfs`) | **PASSED** (Isolated) | Fail-Closed (RAM Injection) |
| **06** | Interactive Shell Spawn | Falco Modern eBPF Engine | **PASSED** (Detected) | Continuous (Syscall Audit) |

**Scorecard Outcome:** `6/6 DRILLS PASSED (100% COMPLIANCE)`

---

## 2. Supply Chain Integrity & Provenance Attestation

Container artifacts are built via GitHub Actions, signed keylessly using Sigstore/Cosign with GitHub OIDC workload identity, and attested with CycloneDX 1.6 Software Bill of Materials (SBOM) predicates.

### Keyless Cosign Signature Verification

```text
Verification for ghcr.io/jason-victor1/polyglot-orders:latest --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
```

### CycloneDX 1.6 SBOM In-Toto Attestation Verification

```text
Certificate subject: https://github.com/jason-victor1/enterprise-devsecops-platform/.github/workflows/build-sign-publish.yml@refs/heads/main
Certificate issuer URL: https://token.actions.githubusercontent.com
GitHub Workflow Trigger: push
GitHub Workflow SHA: adcdd7a64649e22010952066f5f4a4acfd8c0447
GitHub Workflow Repository: jason-victor1/enterprise-devsecops-platform
```

**Decoded Component Graph Excerpt:**
```json
{
  "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
  "bomFormat": "CycloneDX",
  "components": [
    {
      "bom-ref": "pkg:nuget/Microsoft.AspNetCore.App.Runtime.linux-musl-x64@8.0.8?package-id=5bf2cd4c55cb9639",
      "cpe": "cpe:2.3:a:microsoft_aspnetcore_app_runtime_linux_musl_x64:microsoft_aspnetcore_app_runtime_linux_musl_x64_.net:8.0.8:*:*:*:*:*:*:*",
      "name": "Microsoft.AspNetCore.App.Runtime.linux-musl-x64",
      "properties": [
        { "name": "syft:package:foundBy", "value": "dotnet-deps-binary-cataloger" },
        { "name": "syft:package:language", "value": "dotnet" },
        { "name": "syft:package:type", "value": "dotnet" }
      ]
    }
  ]
}
```

---

## 3. Defense-in-Depth Runtime Controls

* **Admission Control (Kyverno):** Restricts image scheduling exclusively to containers with verified Cosign signatures from authorized repository identities.
* **Zero-Trust Network Segmentation (Cilium):** Default-deny baseline drops unapproved east-west communications between internal services.
* **In-Memory Secret Delivery (HashiCorp Vault):** Vault Agent delivers credentials exclusively to an isolated, RAM-backed `tmpfs` volume, keeping process environments clean.
* **Kernel Syscall Auditing (Falco):** Modern eBPF engine traces process execution and terminal allocations, alerting on container shell activity.
