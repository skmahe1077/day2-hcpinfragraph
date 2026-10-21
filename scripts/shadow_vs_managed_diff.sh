#!/usr/bin/env bash
# Simple, local stand-in for "Terraform Search surfaces unmanaged
# resources": lists every EC2 instance actually running in the account
# next to every instance HCP Terraform knows about (via `terraform
# show` on the Stacks state), and prints the difference.
#
# Use this if your org's Terraform Search / Infragraph resource
# inventory isn't wired up to AWS Resource Explorer yet - it gives you
# the same "gap" story without depending on that integration being live.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"

echo "==> Instances HCP Terraform manages (from Stacks state):"
MANAGED_IDS=$(terraform -chdir=../terraform/stacks state list 2>/dev/null \
  | grep aws_instance || true)
if [ -z "$MANAGED_IDS" ]; then
  echo "    (no state available locally - run this from the Stacks workspace, or paste instance IDs from the HCP Terraform UI)"
fi
echo "$MANAGED_IDS"

echo
echo "==> Every EC2 instance actually running in $REGION right now:"
aws ec2 describe-instances --region "$REGION" \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,ManagedBy:Tags[?Key==`ManagedBy`]|[0].Value}' \
  --output table

echo
echo "==> Anything above without ManagedBy=hcp-terraform-stacks is shadow IT."
echo "    That's the 'shadow-reporting-service' instance from create_shadow_resources.sh."
