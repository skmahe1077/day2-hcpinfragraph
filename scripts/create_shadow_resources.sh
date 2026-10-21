#!/usr/bin/env bash
# Creates a few AWS resources OUT OF BAND (plain AWS CLI, no Terraform
# involved) to play the role of "shadow IT" for the Terraform Search /
# Infragraph part of the demo: infra that exists in the account but
# that HCP Terraform has never heard of.
#
# Everything created here is tagged Demo=tec4095-infragraph-shadow so
# scripts/destroy.sh can find and remove it deterministically.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
TAG_KEY="Demo"
TAG_VALUE="tec4095-infragraph-shadow"

echo "==> Using region: $REGION"
aws sts get-caller-identity --output table

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text --region "$REGION")
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'Subnets[0].SubnetId' --output text --region "$REGION")

echo "==> Creating untracked security group 'shadow-reporting-sg' (0.0.0.0/0 on 22)"
SG_ID=$(aws ec2 create-security-group \
  --group-name shadow-reporting-sg \
  --description "Untracked SG created outside Terraform - demo shadow IT" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --region "$REGION" >/dev/null

aws ec2 create-tags --resources "$SG_ID" --region "$REGION" --tags \
  Key=Name,Value=shadow-reporting-sg \
  Key="$TAG_KEY",Value="$TAG_VALUE"

echo "==> Creating untracked EC2 instance 'shadow-reporting-service'"
AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text --region "$REGION")

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --region "$REGION" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=shadow-reporting-service},{Key=$TAG_KEY,Value=$TAG_VALUE}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "==> Creating untracked, untagged S3 bucket for 'leftover exports'"
BUCKET_NAME="infragraph-demo-shadow-exports-$(date +%s)"
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
aws s3api put-bucket-tagging --bucket "$BUCKET_NAME" --tagging \
  "TagSet=[{Key=$TAG_KEY,Value=$TAG_VALUE}]"

cat <<EOF

Shadow IT created:
  Security group: $SG_ID (shadow-reporting-sg)
  Instance:        $INSTANCE_ID (shadow-reporting-service)
  S3 bucket:        $BUCKET_NAME

None of this exists in any Terraform state file. Next: run
scripts/shadow_vs_managed_diff.sh to show the gap, then point at
Terraform Search / Infragraph in the HCP Terraform UI to surface it live.
EOF
