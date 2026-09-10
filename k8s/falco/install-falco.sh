#!/usr/bin/env bash
set -euo pipefail

echo ">>> [FALCO] Adding Falcosecurity Official Helm Repository..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

echo ">>> [FALCO] Deploying Falco via Modern eBPF Probe Driver with Custom Rules..."
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --version 4.3.1 \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --set "customRules.custom-rules\.yaml=null" \
  --set-file "customRules[custom-rules\.yaml]=k8s/falco/rules-custom.yaml" \
  --set falco.json_output=true \
  --set falco.log_stderr=true \
  --set falco.log_syslog=false \
  --set falco.priority=notice \
  --set falco.buffered_outputs=false

echo ">>> [FALCO] Awaiting DaemonSet convergence across all cluster nodes..."
kubectl -n falco rollout status daemonset/falco --timeout=300s
echo ">>> [FALCO] Modern eBPF kernel instrumentation active on all nodes."
