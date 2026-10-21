#!/usr/bin/env bash
# Source this from other scripts to pick up live HCP Vault Dedicated
# connection details from terraform/vault-hcp's outputs. Requires that
# cluster to already be provisioned (bootstrap_vault.sh does this).
VAULT_HCP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform/vault-hcp" && pwd)"

export VAULT_ADDR="$(terraform -chdir="$VAULT_HCP_DIR" output -raw vault_public_endpoint_url)"
export VAULT_TOKEN="$(terraform -chdir="$VAULT_HCP_DIR" output -raw admin_token)"
export VAULT_NAMESPACE="$(terraform -chdir="$VAULT_HCP_DIR" output -raw vault_namespace)"

if [ -z "$VAULT_ADDR" ]; then
  echo "No Vault endpoint found - run scripts/bootstrap_vault.sh first." >&2
  exit 1
fi
