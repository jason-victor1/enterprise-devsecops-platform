# DevSecOps Runtime Control Plane Verification Scorecard

| ID | Attack Vector / Drill | Defensive Layer | Result | Gate Enforcement Mode |
|---|---|---|---|---|
| 01 | Secret Commit Leak | Gitleaks Pre-Commit Hook | PASS | Fail-Closed (Pre-commit Block) |
| 02 | Insecure Deserialization (AST) | Semgrep Polyglot SAST | PASS | Fail-Closed (Static Gate Block) |
| 03 | Unsigned Image Deployment | Kyverno Admission Controller | PASS | Fail-Closed (Admission Rejection) |
| 04 | East-West Lateral Probing | Cilium NetworkPolicy (eBPF) | PASS | Fail-Closed (Default-Deny Drop) |
| 05 | Dynamic Secret In-Memory Leaks | HashiCorp Vault Agent (`tmpfs`) | PASS | Fail-Closed (Zero Env/Disk Leak) |
| 06 | Unauthorized Shell Spawn | Falco Modern eBPF Kernel Driver | PASS | Detection (`execve` Notice Alert) |

**Status**: 6/6 Controls Passed (100% Compliance).
