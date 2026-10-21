#!/usr/bin/env bash
# The actual "Day 2 runbook": generates a new DB credential, writes it
# to HCP Vault Dedicated, then calls Ansible to push it out to the
# target host(s) and restart the app. This script is what the
# Terraform Action in terraform/day2-rotation/actions.tf invokes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_vault_env.sh"

NEW_PASSWORD="rotated-$(openssl rand -hex 8)"

echo "==> [1/3] Rotating credential in HCP Vault Dedicated ($VAULT_ADDR, secret/infragraph-demo/dbcred)"
vault kv put secret/infragraph-demo/dbcred \
  username="webapp" \
  password="$NEW_PASSWORD"

echo "==> [2/3] Handing off to Ansible to push the new credential to hosts"
cd "$SCRIPT_DIR/../ansible"
ansible-playbook -i inventory.ini rotate_credential.yml \
  -e "new_password=${NEW_PASSWORD}"

echo "==> [3/3] Rotation complete. New credential is live in HCP Vault and on target hosts."
