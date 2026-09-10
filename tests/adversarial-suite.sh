#!/usr/bin/env bash
# ==============================================================================
# Automated Adversarial Verification Suite & Platform Security Scorecard
# Target: 7-Microservice Polyglot DevSecOps Reference Platform
# ==============================================================================
set -euo pipefail

# ANSI Color Palettes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Execution Counters
TOTAL_TESTS=6
PASSED_TESTS=0
FAILED_TESTS=0

# Scorecard Results Cache (ID | Attack Vector | Defense Layer | Status)
declare -a SCORECARD_RESULTS=()

# ------------------------------------------------------------------------------
# Safe Teardown & Idempotency Trap
# ------------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  echo -e "\n${BLUE}[TEARDOWN]${NC} Cleaning up temporary adversarial artifacts..."

  # Revert temporary SAST modifications
  if [ -f "services/analytics/server.py" ]; then
    git checkout -- services/analytics/server.py 2>/dev/null || true
  fi

  # Remove temporary secret test files from staging
  rm -f services/orders/leak_test.tmp 2>/dev/null || true
  git reset HEAD services/orders/leak_test.tmp 2>/dev/null || true

  # Delete rogue unsigned pods from Kubernetes
  kubectl -n production delete pod rogue-catalog --ignore-not-found=true --grace-period=0 --force 2>/dev/null || true

  if [ ${exit_code} -ne 0 ] && [ ${FAILED_TESTS} -eq 0 ]; then
    echo -e "${RED}[ERROR] Test harness exited prematurely with code ${exit_code}.${NC}"
  fi
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Helper Loggers
# ------------------------------------------------------------------------------
log_section() {
  echo -e "\n${BOLD}${CYAN}================================================================================${NC}"
  echo -e "${BOLD}${CYAN}>>> RUNNING DRILL: $1${NC}"
  echo -e "${BOLD}${CYAN}================================================================================${NC}"
}

record_result() {
  local id="$1"
  local vector="$2"
  local layer="$3"
  local status="$4"

  if [ "${status}" == "PASSED" ]; then
    SCORECARD_RESULTS+=("${id}|${vector}|${layer}|${GREEN}[PASSED - BLOCKED]${NC}")
    ((++PASSED_TESTS))
  else
    SCORECARD_RESULTS+=("${id}|${vector}|${layer}|${RED}[FAILED - BREACHED]${NC}")
    ((++FAILED_TESTS))
  fi
}

# ------------------------------------------------------------------------------
# DRILL 1: Secret Commit Interception (Track A - Gitleaks)
# ------------------------------------------------------------------------------
run_drill_1() {
  log_section "01 - Secret Commit Interception via Staged Gitleaks Hook"
  echo "Simulating accidental credential commit into local git working tree..."

  local target_file="services/orders/leak_test.tmp"
  echo "string apiKey = \"$(printf '%s%s' 'shop-prod-secret-' '9876543210abcdef0123456789abcdef')\";" > "${target_file}"
  git add -f "${target_file}"

  local gitleaks_status=0
  if command -v gitleaks &>/dev/null; then
    gitleaks protect --verbose --redact --config=.gitleaks.toml --staged || gitleaks_status=$?
  else
    docker run --rm -v "$(pwd):/app" -w /app zricethezav/gitleaks:v8.18.2 protect \
      --verbose --redact --config=.gitleaks.toml --staged || gitleaks_status=$?
  fi

  # Clean up the staged file immediately
  git rm -f "${target_file}" &>/dev/null || rm -f "${target_file}"

  if [ ${gitleaks_status} -ne 0 ]; then
    echo -e "${GREEN}✔ SUCCESS:${NC} Gitleaks intercepted high-entropy credential pattern (Exit Code: ${gitleaks_status})."
    record_result "01" "Secret Commit Leak" "Gitleaks Pre-Commit Hook" "PASSED"
  else
    echo -e "${RED}✘ FAILURE:${NC} Gitleaks failed to intercept the credential commit."
    record_result "01" "Secret Commit Leak" "Gitleaks Pre-Commit Hook" "FAILED"
  fi
}

# ------------------------------------------------------------------------------
# DRILL 2: Static Vulnerability AST Detection (Track A - Semgrep SAST)
# ------------------------------------------------------------------------------
run_drill_2() {
  log_section "02 - Insecure Deserialization Static AST Gating"
  echo "Injecting unsafe YAML deserialization vulnerability into services/analytics/server.py..."

  cat << 'EOF' >> services/analytics/server.py

def unsafe_telemetry_deserializer(payload_stream):
    import yaml
    return yaml.load(payload_stream, Loader=yaml.Loader)
EOF

  local semgrep_status=0
  if command -v semgrep &>/dev/null; then
    semgrep scan --config=.semgrep/rules.yml --error services/analytics/server.py || semgrep_status=$?
  else
    docker run --rm -v "$(pwd):/src" returntocorp/semgrep:1.70.0 semgrep scan \
      --config=/src/.semgrep/rules.yml --error /src/services/analytics/server.py || semgrep_status=$?
  fi

  # Immediately revert source modifications
  git checkout -- services/analytics/server.py

  if [ ${semgrep_status} -eq 1 ]; then
    echo -e "${GREEN}✔ SUCCESS:${NC} Semgrep AST engine flagged unsafe deserialization (Exit Code: 1)."
    record_result "02" "Insecure Deserialization" "Semgrep Polyglot SAST" "PASSED"
  else
    echo -e "${RED}✘ FAILURE:${NC} Semgrep allowed vulnerable code pattern through static gate (Exit Code: ${semgrep_status})."
    record_result "02" "Insecure Deserialization" "Semgrep Polyglot SAST" "FAILED"
  fi
}

# ------------------------------------------------------------------------------
# DRILL 3: Supply Chain Provenance Gate (Track B - Kyverno Cosign Verification)
# ------------------------------------------------------------------------------
run_drill_3() {
  log_section "03 - Supply Chain Provenance & Cryptographic Signature Enforcement"
  echo "Attempting to schedule unsigned image 'enterprise/catalog:tampered' into namespace 'production'..."

  local admission_output=""
  local admission_status=0

  admission_output=$(kubectl run rogue-catalog \
    --image=enterprise/catalog:tampered \
    --namespace=production \
    --restart=Never \
    --overrides='{
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 65532,
          "seccompProfile": { "type": "RuntimeDefault" }
        },
        "containers": [{
          "name": "catalog",
          "image": "enterprise/catalog:tampered",
          "securityContext": {
            "allowPrivilegeEscalation": false,
            "readOnlyRootFilesystem": true,
            "capabilities": { "drop": ["ALL"] }
          }
        }]
      }
    }' 2>&1) || admission_status=$?

  if [ ${admission_status} -ne 0 ] && echo "${admission_output}" | grep -Eq "check-image-signatures|failed to verify signature|denied the request"; then
    echo -e "${GREEN}✔ SUCCESS:${NC} Kyverno validating webhook blocked unsigned container image."
    echo -e "${YELLOW}Webhook Output:${NC} $(echo "${admission_output}" | grep -E "blocked by|failed to verify" | head -n 1)"
    record_result "03" "Unsigned Image Deploy" "Kyverno Image Signature Gate" "PASSED"
  else
    echo -e "${RED}✘ FAILURE:${NC} Admission controller allowed unsigned image to schedule."
    kubectl -n production delete pod rogue-catalog --ignore-not-found=true 2>/dev/null || true
    record_result "03" "Unsigned Image Deploy" "Kyverno Image Signature Gate" "FAILED"
  fi
}

# ------------------------------------------------------------------------------
# DRILL 4: Zero-Trust East-West Boundary (Track B - Cilium CNI NetworkPolicy)
# ------------------------------------------------------------------------------
run_drill_4() {
  log_section "04 - East-West Micro-Segmentation Lateral Probing"
  echo "Executing unauthorized lateral network probe from Notification pod to Inventory API (:8081)..."

  local notif_pod
  notif_pod=$(kubectl -n production get pods -l app=notification -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -z "${notif_pod}" ]; then
    echo -e "${RED}✘ CONFIG ERROR:${NC} Notification pod not found in 'production' namespace."
    record_result "04" "Lateral Network Probing" "Cilium NetworkPolicy (eBPF)" "FAILED"
    return
  fi

  local probe_status=0
  local probe_output=""

  probe_output=$(kubectl -n production exec "${notif_pod}" -c notification -- ruby -e '
    require "net/http"
    require "uri"
    uri = URI("http://inventory.production.svc.cluster.local:8081/healthz")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 2
    begin
      http.start { http.get(uri.path) }
      exit 0
    rescue Net::OpenTimeout, Errno::ETIMEDOUT, Errno::EHOSTUNREACH => e
      $stderr.puts "PACKET_DROPPED: #{e.class}"
      exit 42
    end
  ' 2>&1) || probe_status=$?

  if [ ${probe_status} -eq 42 ] || echo "${probe_output}" | grep -q "PACKET_DROPPED"; then
    echo -e "${GREEN}✔ SUCCESS:${NC} Cilium eBPF engine dropped packet at network perimeter (Exit Code: ${probe_status})."
    record_result "04" "Lateral Network Probing" "Cilium NetworkPolicy (eBPF)" "PASSED"
  else
    echo -e "${RED}✘ FAILURE:${NC} Notification service successfully routed packets to Inventory service."
    record_result "04" "Lateral Network Probing" "Cilium NetworkPolicy (eBPF)" "FAILED"
  fi
}

# ------------------------------------------------------------------------------
# DRILL 5: Dynamic Secret Memory Isolation (Track B - HashiCorp Vault tmpfs)
# ------------------------------------------------------------------------------
run_drill_5() {
  log_section "05 - Dynamic Secret In-Memory Isolation & Environment Sanitization"
  echo "Validating Orders workload secret isolation and verifying absence from process environment..."

  local orders_pod
  orders_pod=$(kubectl -n production get pods -l app=orders -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -z "${orders_pod}" ]; then
    echo -e "${RED}✘ CONFIG ERROR:${NC} Orders pod not found in 'production' namespace."
    record_result "05" "Dynamic Secret Leaks" "Vault Agent & tmpfs Mount" "FAILED"
    return
  fi

  # 1. Assert secrets file exists
  local has_secret=0
  kubectl -n production exec "${orders_pod}" -c orders -- test -f /vault/secrets/config.json || has_secret=$?

  # 2. Assert secret volume is backed by RAM (tmpfs)
  local is_tmpfs=0
  kubectl -n production exec "${orders_pod}" -c orders -- df -T /vault/secrets | grep -q "tmpfs" || is_tmpfs=$?

  # 3. Assert secrets are completely absent from environment variables
  local env_leak=0
  local env_scan
  env_scan=$(kubectl -n production exec "${orders_pod}" -c orders -- env | grep -E "apiKey|catalogAuthToken|ord-live" || true)

  if [ -n "${env_scan}" ]; then
    env_leak=1
  fi

  if [ ${has_secret} -eq 0 ] && [ ${is_tmpfs} -eq 0 ] && [ ${env_leak} -eq 0 ]; then
    echo -e "${GREEN}✔ SUCCESS:${NC} Credentials delivered exclusively via tmpfs RAM volume."
    echo -e "${GREEN}✔ SUCCESS:${NC} Zero secrets discovered in process environment variables."
    record_result "05" "Dynamic Secret Leaks" "Vault Agent & tmpfs Mount" "PASSED"
  else
    echo -e "${RED}✘ FAILURE:${NC} Secret isolation validation failed (File: ${has_secret}, tmpfs: ${is_tmpfs}, EnvLeak: ${env_leak})."
    record_result "05" "Dynamic Secret Leaks" "Vault Agent & tmpfs Mount" "FAILED"
  fi
}

# ------------------------------------------------------------------------------
# DRILL 6: Runtime Kernel Syscall Detection (Track B - Falco Modern eBPF)
# ------------------------------------------------------------------------------
run_drill_6() {
  log_section "06 - Runtime Threat Detection via Kernel Syscall Interception"
  echo "Spawning unauthorized interactive shell inside Dashboard pod..."

  local dash_pod
  dash_pod=$(kubectl -n production get pods -l app=dashboard -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -z "${dash_pod}" ]; then
    echo -e "${RED}✘ CONFIG ERROR:${NC} Dashboard pod not found in 'production' namespace."
    record_result "06" "Interactive Shell Spawn" "Falco Modern eBPF Engine" "FAILED"
    return
  fi

  # Execute shell spawn to trigger the syscall tracepoint
  kubectl -n production exec -it "${dash_pod}" -c dashboard -- /bin/sh -c "echo 'simulated_adversary_exec'; whoami" >/dev/null 2>&1

  echo "Polling Falco audit log stream for eBPF event capture..."
  local falco_detected=0
  local max_attempts=10

  for ((i=1; i<=max_attempts; i++)); do
    local logs
    logs=$(kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=100 2>/dev/null || true)
    if echo "${logs}" | grep -Eq "Unauthorized Interactive Shell Spawn in Production|A shell was spawned in a container"; then
      falco_detected=1
      break
    fi
    sleep 1
  done

  if [ ${falco_detected} -eq 1 ]; then
    echo -e "${GREEN}✔ SUCCESS:${NC} Falco modern eBPF engine captured unauthorized execve() syscall."
    record_result "06" "Interactive Shell Spawn" "Falco Modern eBPF Engine" "PASSED"
  else
    echo -e "${RED}✘ FAILURE:${NC} Falco failed to capture interactive shell spawn within timeout window."
    record_result "06" "Interactive Shell Spawn" "Falco Modern eBPF Engine" "FAILED"
  fi
}

# ------------------------------------------------------------------------------
# PLATFORM SECURITY SCORECARD RENDERER
# ------------------------------------------------------------------------------
render_scorecard() {
  echo -e "\n"
  echo -e "${BOLD}${CYAN}========================================================================================================================${NC}"
  echo -e "${BOLD}${CYAN}                                       DEVSECOPS PLATFORM VERIFICATION SCORECARD                                        ${NC}"
  echo -e "${BOLD}${CYAN}========================================================================================================================${NC}"
  printf "${BOLD}%-4s | %-32s | %-30s | %-20s${NC}\n" "ID" "ATTACK VECTOR / TEST CASE" "DEFENSIVE LAYER TESTED" "VERIFICATION STATUS"
  echo -e "-----+----------------------------------+--------------------------------+----------------------------------------------"

  for entry in "${SCORECARD_RESULTS[@]}"; do
    IFS="|" read -r id vector layer status <<< "${entry}"
    printf "%-4s | %-32s | %-30s | %b\n" "${id}" "${vector}" "${layer}" "${status}"
  done

  echo -e "========================================================================================================================"
  local pass_pct=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))

  if [ ${FAILED_TESTS} -eq 0 ]; then
    echo -e "${BOLD}${GREEN}SUMMARY: ${PASSED_TESTS}/${TOTAL_TESTS} DRILLS PASSED (${pass_pct}% COMPLIANCE) - ALL GATES OPERATING IN FAIL-CLOSED MODE${NC}"
    echo -e "${BOLD}${CYAN}========================================================================================================================${NC}\n"
    exit 0
  else
    echo -e "${BOLD}${RED}SUMMARY: ${PASSED_TESTS}/${TOTAL_TESTS} DRILLS PASSED, ${FAILED_TESTS} VULNERABILITIES DETECTED (${pass_pct}% COMPLIANCE)${NC}"
    echo -e "${BOLD}${CYAN}========================================================================================================================${NC}\n"
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# MAIN EXECUTION FLOW
# ------------------------------------------------------------------------------
main() {
  echo -e "${BOLD}${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║          ENTERPRISE DEVSECOPS CAPSTONE AUTOMATED VERIFICATION HARNESS       ║"
  echo "║          EVALUATING ZERO-TRUST RUNTIME & SUPPLY-CHAIN CONTROL PLANES         ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  run_drill_1
  run_drill_2
  run_drill_3
  run_drill_4
  run_drill_5
  run_drill_6

  render_scorecard
}

main "$@"
