#!/usr/bin/env bash
# Tears down everything this demo created:
#   - Stacks-managed AWS infra (via HCP Terraform)
#   - the day2-rotation Actions module state
#   - the HCP Vault Dedicated cluster (billed hourly - this matters most)
#   - the out-of-band "shadow IT" resources (tagged Demo=tec4095-infragraph-shadow)
#
# Run this as soon as the talk/rehearsal is done - the webapp instances,
# shadow resources, and HCP Vault cluster are all real, billable resources.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Destroying day2-rotation Terraform state"
terraform -chdir="$SCRIPT_DIR/../terraform/day2-rotation" destroy -auto-approve || true

echo "==> Destroying HCP Vault Dedicated cluster (billed hourly - priority teardown)"
terraform -chdir="$SCRIPT_DIR/../terraform/vault-hcp" destroy -auto-approve || true

echo "==> Destroying Stacks-managed deployments (dev/staging/prod)"
echo "    Run this from the HCP Terraform UI (Stacks > destroy deployment) for each"
echo "    of dev/staging/prod, or via: terraform-cli stacks destroy (if installed)."

echo "==> Removing out-of-band shadow IT resources"
TAG_KEY="Demo"
TAG_VALUE="tec4095-infragraph-shadow"

INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$INSTANCE_IDS" ]; then
  echo "    Terminating instances: $INSTANCE_IDS"
  aws ec2 terminate-instances --region "$REGION" --instance-ids $INSTANCE_IDS >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INSTANCE_IDS
fi

SG_IDS=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" \
  --query 'SecurityGroups[].GroupId' --output text)
for sg in $SG_IDS; do
  echo "    Deleting security group: $sg"
  aws ec2 delete-security-group --region "$REGION" --group-id "$sg" || true
done

BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text \
  | tr '\t' '\n' | grep '^infragraph-demo-shadow-exports-' || true)
for bucket in $BUCKETS; do
  echo "    Emptying and deleting bucket: $bucket"
  aws s3 rm "s3://$bucket" --recursive >/dev/null 2>&1 || true
  aws s3api delete-bucket --bucket "$bucket" --region "$REGION" || true
done

echo "==> Done. Double-check the AWS console / HCP Terraform org (Devopstronaut) and the HCP Vault cluster list for stragglers."
