#!/usr/bin/env bash
# Builds the golden AMI with Packer, registers it in the HCP Packer
# registry, then promotes it to the "production" channel so the Stacks
# component (terraform/stacks/components.tfcomponent.hcl) can pick it up
# via the hcp_packer_artifact data source.
#
# Requires: packer CLI, HCP_CLIENT_ID / HCP_CLIENT_SECRET env vars,
# HCP_PACKER_REGISTRY=1 (enables registry metadata push), and an AWS
# session valid in the target account/region.
set -euo pipefail

cd "$(dirname "$0")/../terraform/packer"

export HCP_PACKER_REGISTRY=1

echo "==> packer init"
packer init golden-ami.pkr.hcl

echo "==> packer build"
packer build golden-ami.pkr.hcl

echo "==> Promote latest iteration on 'infragraph-demo-webapp' to 'production' channel"
echo "    (run in the HCP Packer UI/CLI, or via: hcp packer channel create-assignment ...)"
echo "    This step is manual by design for the demo - it's the moment"
echo "    you narrate on stage: 'now promoting this build to production'."
