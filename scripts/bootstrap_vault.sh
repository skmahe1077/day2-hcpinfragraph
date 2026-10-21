#!/usr/bin/env bash
# Provisions a real HCP Vault Dedicated cluster (dev tier, public
# endpoint) via terraform/vault-hcp, then seeds it with the "webapp DB
# credential" that the Day 2 rotation runbook will rotate.
#
# This is a real, billable cluster - run scripts/destroy.sh as soon as
# the demo/rehearsal is done.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Provisioning HCP Vault Dedicated (HVN + cluster + admin token)"
terraform -chdir="$SCRIPT_DIR/../terraform/vault-hcp" init
terraform -chdir="$SCRIPT_DIR/../terraform/vault-hcp" apply -auto-approve

echo "==> Waiting for cluster to report an endpoint (can take a few minutes on first apply)"
source "$SCRIPT_DIR/_vault_env.sh"

echo "==> Vault endpoint: $VAULT_ADDR (namespace: $VAULT_NAMESPACE)"

echo "==> Enabling kv-v2 secrets engine at secret/"
vault secrets enable -path=secret kv-v2 2>/dev/null || true

echo "==> Seeding initial webapp DB credential"
vault kv put secret/infragraph-demo/dbcred \
  username="webapp" \
  password="initial-$(openssl rand -hex 8)"

echo "==> Current credential:"
vault kv get secret/infragraph-demo/dbcred

cat <<EOF

To talk to this cluster from another shell, run:
  source scripts/_vault_env.sh
EOF
