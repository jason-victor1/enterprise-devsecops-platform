#!/usr/bin/env bash
set -euo pipefail

echo ">>> [CNI] Validating Kubernetes Cluster API reachability..."
kubectl cluster-info --context kind-devsecops-cluster

echo ">>> [CNI] Adding Cilium Official Helm Repository..."
helm repo add cilium https://helm.cilium.io/
helm repo update

echo ">>> [CNI] Deploying Cilium CNI in eBPF Strict Policy Enforcement Mode..."
helm install cilium cilium/cilium \
  --version 1.15.5 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set operator.replicas=1 \
  --set tunnel-protocol=vxlan \
  --set policyEnforcement=always \
  --set kubeProxyReplacement=false

echo ">>> [CNI] Awaiting Cilium DaemonSet and Operator rollouts..."
kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s

echo ">>> [CNI] Verifying Pod Network Connectivity & CoreDNS Readiness..."
kubectl -n kube-system rollout status deployment/coredns --timeout=120s
echo ">>> [CNI] Cilium eBPF Engine successfully established."
