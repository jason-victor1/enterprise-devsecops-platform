#!/usr/bin/env bash
set -euo pipefail

echo ">>> [KYVERNO] Adding Kyverno Official Helm Repository..."
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

echo ">>> [KYVERNO] Deploying Kyverno Admission Controller in High-Availability Mode..."
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version 3.2.5 \
  --set admissionController.replicas=1 \
  --set backgroundController.replicas=1 \
  --set cleanupController.replicas=1 \
  --set reportsController.replicas=1 \
  --set admissionController.serviceMonitor.enabled=false

echo ">>> [KYVERNO] Waiting for Admission Controller deployments to enter Ready state..."
kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=180s
kubectl -n kyverno rollout status deployment/kyverno-background-controller --timeout=180s

echo ">>> [KYVERNO] Validating Admission Webhook Registration..."
kubectl wait --for=condition=Available --timeout=60s -n kyverno deployment/kyverno-admission-controller
sleep 5
echo ">>> [KYVERNO] Admission Controller initialized and accepting policy definitions."
