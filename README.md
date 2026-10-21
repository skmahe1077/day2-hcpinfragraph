# Day 2 or Never - TEC-4095 demo

Demo repo for the talk *"Day 2 or Never: Closing the Multicloud Operations Gap
with HCP Terraform and Project Infragraph."*

Walks through one iteration of the ILM (Infrastructure Lifecycle Management)
loop against real AWS infra, using:

- **Terraform Search** - surface unmanaged ("shadow IT") resources
- **Project Infragraph** - the graph connecting infra, ownership, policy, and
  operational context across everything below
- **HCP Packer** - golden image build + provenance
- **Stacks** - one standardized deployment pattern across dev/staging/prod
- **Terraform Actions + HCP Vault Dedicated + Ansible** - a codified Day 2
  runbook (credential rotation)

The full walkthrough is in [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md) -
start there.

## Layout

```
terraform/
  stacks/                 Stacks: component + 3 deployments (dev/staging/prod)
    components.tfcomponent.hcl
    deployments.tfdeploy.hcl
    components/webapp/    the actual module (VPC default + SG + EC2)
  packer/
    golden-ami.pkr.hcl    builds + registers the AMI the Stacks component consumes
  day2-rotation/
    actions.tf            Terraform Action: rotate DB credential (Vault + Ansible)
  vault-hcp/
    main.tf               HCP Vault Dedicated: HVN + cluster (dev tier) + admin token
ansible/
  rotate_credential.yml   pushes a rotated credential to the target host
scripts/
  create_shadow_resources.sh     out-of-band AWS resources (the "shadow IT")
  shadow_vs_managed_diff.sh      local fallback for the Search/Infragraph gap demo
  build_and_promote_image.sh     packer build + HCP Packer registry push
  bootstrap_vault.sh             provisions the HCP Vault cluster, seeds initial credential
  rotate_credential.sh           the actual Day 2 runbook (called by the Action)
  _vault_env.sh                  shared helper: exports VAULT_ADDR/TOKEN/NAMESPACE from vault-hcp outputs
  destroy.sh                     tears down everything real/billable
docs/
  DEMO_SCRIPT.md          step-by-step narration for the live demo
```

## Everything runs through HCP Terraform, not local state

This is a demo *for* HCP Terraform, so every piece's run history/state lives
in the org, not on your laptop:

- **Stacks** (`terraform/stacks/`) only run in HCP Terraform - there's no
  local-apply path. Create the Stack in the HCP Terraform UI by connecting
  this repo and pointing it at `terraform/stacks/`; plans/applies for
  dev/staging/prod happen there, not via local `terraform` commands.
- **day2-rotation** (`terraform/day2-rotation/actions.tf`) uses a `cloud`
  block targeting workspace `infragraph-demo-day2-rotation` in org
  `Devopstronaut` - running `terraform apply` locally still creates a real,
  visible run in that workspace. Set this workspace's **Execution Mode to
  Local** in its HCP Terraform settings: the Action shells out to
  `ansible-playbook`, which a remote HCP Terraform execution sandbox
  can't reach.
- **Vault** is HCP Vault Dedicated (`terraform/vault-hcp/`), not a local
  container - a real, billed-hourly cluster provisioned by its own
  `cloud`-backed workspace (`infragraph-demo-vault`).
- **HCP Packer** registry push happens from wherever `packer build` runs
  (your laptop or CI) - the registry itself is HCP-hosted, so the image
  provenance Stacks consumes is already "in HCP."

## Prerequisites

- HCP Terraform org: **Devopstronaut** (workspace/stack prefix: `infragraph-demo`)
  - `terraform login` done locally (CLI-driven workspace auth)
  - Stack created in the UI, pointed at `terraform/stacks/`
  - Workspace `infragraph-demo-day2-rotation` created with Execution Mode = Local
  - Workspace `infragraph-demo-vault` created (any execution mode - no local
    tool dependencies)
- AWS CLI configured with credentials for the target account, region `eu-west-1`
  (check with `aws sts get-caller-identity` - these need to be valid before
  running anything that touches real infra)
- `terraform`, `packer`, `vault`, `ansible-playbook` CLIs installed
- HCP service principal credentials (`HCP_CLIENT_ID` / `HCP_CLIENT_SECRET`) -
  used for both the HCP Packer registry push and the HCP Vault provider

## Everything here is real, billable infra

`create_shadow_resources.sh` and the Stacks `dev` deployment both create real
AWS resources (EC2 instances, security groups, an S3 bucket for shadow
resources). `bootstrap_vault.sh` provisions a real HCP Vault Dedicated
cluster, billed hourly from the moment it's created.
**Run `scripts/destroy.sh` as soon as the demo/rehearsal is done.**
