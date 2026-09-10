#!/usr/bin/env bash
set -euo pipefail

echo ">>> [VAULT] Installing HashiCorp Vault Helm Chart with PSS-Restricted Compliant Injector..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root-dev-token-insecure" \
  --set "injector.enabled=true" \
  --set "injector.agentDefaults.runAsUser=65532" \
  --set "injector.agentDefaults.runAsGroup=65532" \
  --set "injector.agentDefaults.securityContext.allowPrivilegeEscalation=false" \
  --set "injector.agentDefaults.securityContext.capabilities.drop={ALL}" \
  --set "injector.agentDefaults.securityContext.readOnlyRootFilesystem=true" \
  --set "injector.agentDefaults.securityContext.seccompProfile.type=RuntimeDefault"

echo ">>> [VAULT] Waiting for Vault Server and Injector to enter Ready state..."
kubectl -n vault rollout status deployment/vault-agent-injector --timeout=180s
kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s

echo ">>> [VAULT] Configuring In-Cluster Kubernetes Auth Engine..."
kubectl -n vault exec -i vault-0 -- /bin/sh << 'EOF'
set -e
export VAULT_TOKEN="root-dev-token-insecure"
export VAULT_ADDR="http://127.0.0.1:8200"

# Enable KV v2 secret engine at path secret/ if not pre-mounted
vault secrets enable -path=secret kv-v2 2>/dev/null || true

# Provision baseline secrets for Orders and Payment tiers
vault kv put secret/orders/config \
  api_key="ord-live-secret-8f92b47e192a48" \
  catalog_auth_token="cat-token-99887766554433"

vault kv put secret/payment/credentials \
  merchant_id="merch-pci-9843-enterprise" \
  encryption_key="AES256-4c9f8a7e6b5d4c3b2a10"

# Enable Kubernetes native service-account authentication
vault auth enable kubernetes 2>/dev/null || true

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Establish access control policies
vault policy write orders-policy - << 'POL'
path "secret/data/orders/config" {
  capabilities = ["read"]
}
POL

vault policy write payment-policy - << 'POL'
path "secret/data/payment/credentials" {
  capabilities = ["read"]
}
POL

# Bind Kubernetes ServiceAccounts to Vault Policies
vault write auth/kubernetes/role/orders-role \
  bound_service_account_names=orders-sa \
  bound_service_account_namespaces=production \
  policies=orders-policy \
  ttl=1h

vault write auth/kubernetes/role/payment-role \
  bound_service_account_names=payment-sa \
  bound_service_account_namespaces=production \
  policies=payment-policy \
  ttl=1h

echo ">>> [VAULT] Kubernetes Auth Engine, Policies, and Roles successfully initialized."
EOF
