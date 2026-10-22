# Demo script - TEC-4095 "Day 2 or Never"

Org: `Devopstronaut` · Workspace/stack prefix: `infragraph-demo` · Region: `eu-west-1`

Narrative: the ILM loop - **surface** unmanaged infra, **govern** it, **standardise**
new deployments, **codify** Day 2 ops, and let **Infragraph** tie all four stages
together into one graph instead of four disconnected tools.

## 0. Before you go on stage

```bash
aws sts get-caller-identity          # confirm AWS creds are live
terraform login                      # confirm CLI auth to HCP Terraform org Devopstronaut
./scripts/bootstrap_vault.sh         # provisions HCP Vault Dedicated, seeds initial DB credential
```

`bootstrap_vault.sh` provisions a real HCP Vault Dedicated cluster (dev
tier, public endpoint) - first apply can take a few minutes, so run this
well before you're on stage, not as part of the live demo.

Everything below runs as real HCP Terraform runs, not local state - make sure
this is set up in org `Devopstronaut` *before* you're on stage:

- Workspace **`infragraph-demo-day2-rotation`** created with **Execution
  Mode = Local** (Settings → General). Local execution is required here so
  the Action can shell out to `ansible-playbook` - a remote HCP Terraform run
  sandbox can't reach it.
- Workspace **`infragraph-demo-vault`** created (backs `terraform/vault-hcp`).
- `terraform/packer` built+promoted at least once (`scripts/build_and_promote_image.sh`)
  so a "production" AMI channel exists before the Stacks apply.

### Create the Stack (one-time)

1. HCP Terraform UI → pick the **project** that also holds the two workspaces above
   (keep the Stack and its workspaces in the same project - simplifies which project a
   provider-credentials variable set needs to target, see below).
2. New → Stack → choose your GitHub VCS connection (authorize the "HCP Terraform" GitHub
   App for this repo if it isn't connected yet) → repository
   `skmahe1077/day2-hcpinfragraph` → branch `main` → **config path `terraform/stacks`**.
3. Name it. Validation note: the name field only accepts **letters, numbers, dashes, and
   underscores** - no spaces.
4. First fetch/plan will likely fail a couple of times on real config issues before it's
   clean - the ones we actually hit, in order:
   - Missing `terraform/stacks/.terraform-version` (Stacks need this to pick a Core
     version - classic workspaces let you set this in the UI, Stacks don't).
   - Missing/incomplete `.terraform.lock.hcl` at the stack root **and** inside each
     component module - must include a hash for `linux_amd64` (the TFC agent's
     platform), not just whatever platform you last ran `terraform init` on locally.
   - `data` blocks are **not valid** at the top level of a `.tfcomponent.hcl` file - any
     provider data lookup (e.g. `hcp_packer_artifact`) has to live inside its own
     component module and get exposed as an output, referenced via
     `component.<name>.<output>`.
   - The `orchestrate "auto_approve"` block is deprecated and has real schema
     drift from what you'd guess: a `check` block's error field is `reason`, not
     `error_message`, and `context.deployment.name` isn't a thing. Use
     `deployment_group` + `deployment_auto_approve` instead (already wired up this way
     in `deployments.tfdeploy.hcl` - non-prod deployments sit in an auto-approving
     group, prod is left out of it to fall back to manual approval).

### Give the Stack's providers credentials (one-time)

Stacks don't inherit a workspace's ambient process environment - the `aws`/`hcp`
provider blocks in `components.tfcomponent.hcl` need real `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` / `HCP_CLIENT_ID` / `HCP_CLIENT_SECRET` wired in explicitly, or
every plan fails with provider-auth errors (`hcp` tries an interactive browser OAuth
login and fails because the TFC agent has no browser; `aws` fails with "no valid
credential sources").

1. Create a **variable set** (org Settings → Variable sets) with those four values as
   sensitive, `env`-category variables.
2. **Apply it to the project** that holds the Stack (`varsets/:id/relationships/projects`
   if going via API) - note that just setting the varset's *owning* project does **not**
   apply it anywhere; it's a separate action.
3. Even with that applied, a Stack doesn't auto-inject the varset's values as process env
   vars the way a classic workspace does - `deployments.tfdeploy.hcl` has to explicitly
   pull them via a `store "varset"` block (matched by the variable set's **name**, not
   its ID) and pass them through as **`ephemeral = true`** deployment inputs (a plain
   `sensitive` variable isn't enough - store-sourced values are rejected unless the
   receiving variable opts into `ephemeral`). Already wired up this way in this repo -
   if you rename the variable set, update the `name` in the `store` block to match.

### Activate Infragraph (one-time, do this well before you're on stage)

Infragraph is a separate HCP product from HCP Terraform/Stacks - having the Stack and
workspaces running does **not** populate it. It needs to be activated and given explicit
connections. Requires: Admin/Owner role on the HCP org, and the HCP Terraform org on a
Standard plan or above (`Devopstronaut` is on Premium, which includes it).

1. **Create a team + token in HCP Terraform** for the connection: org `Devopstronaut` →
   Settings → Teams → create a team (e.g. `infragraph-connection`) → grant it
   **`read-projects`** and **`read-workspaces`** org-access → generate a team API token.
   (A team with no org-access grants can be created but is useless here - the connection
   will authenticate fine and still see nothing until those two permissions are set.)
2. **Activate Infragraph**: `portal.cloud.hashicorp.com` → Organization dashboard →
   Infragraph section → Activate, pasting in the team token from step 1.
3. **Add connections** (Infragraph → Resource graph → Overview → Create Connection) -
   each one is what actually populates the graph:
   - **HCP Terraform** - same team token, pulls in the Stack + both workspaces + their runs.
   - **AWS** - click "View Terraform module in Registry" to get a generated
     `hashicorp/infragraph-connector-permissions/aws` module block (OIDC-federated IAM
     role, read-only `List*`/`Describe*`/`Get*` permissions, no write access). Apply it
     against the target account with a real AWS session. Watch for this gotcha: if an
     OIDC provider for `idp.hashicorp.com/oidc/...` already exists in the account (e.g.
     from an earlier attempt), the apply fails with `EntityAlreadyExists` - `terraform
     import` the existing provider ARN
     (`aws_iam_openid_connect_provider.hcp_infragraph`) instead of recreating it, then
     re-apply; expect it to correct a stale `client_id_list`/`thumbprint_list` on that
     provider as part of the same apply. Scope the connection to "Specific Accounts" with
     the target account ID for a single-account demo.
   - **HCP Packer** - so the AMI/build lineage shows up on the graph.
4. Give it a few minutes after creating each connection for the first sync to land before
   relying on it live on stage.

## 1. Surface the gap (Terraform Search / Infragraph)

```bash
./scripts/create_shadow_resources.sh
```

This creates a real EC2 instance, security group, and S3 bucket **outside**
Terraform entirely - plain AWS CLI calls. Narrate: "this is how most shadow IT
is born - someone needed something fast."

Then:
- If your org has resource-inventory / Terraform Search wired to AWS, open
  HCP Terraform → Infragraph and search for the account - point at the
  `shadow-reporting-service` instance showing up with no owning workspace.
- Otherwise, run the local fallback:

```bash
./scripts/shadow_vs_managed_diff.sh
```

and narrate the diff between "what Terraform manages" and "what's actually
running."

## 2. Standardise the real deployment (HCP Packer + Stacks)

```bash
./scripts/build_and_promote_image.sh     # builds + registers golden AMI
```

Open HCP Packer in the UI, show the registry entry for
`infragraph-demo-webapp`, point out the metadata (build time, source commit
if CI is wired up).

Then trigger the Stack from the HCP Terraform UI (push to the connected
branch, or hit "Start a new plan" on the Stack): there is no local
`terraform apply` for Stacks, the run happens entirely in HCP Terraform.

Narrate while the plan runs: one component (`components/webapp`), three
deployments (`dev`, `staging`, `prod`) in `deployments.tfdeploy.hcl`, same
code, same golden AMI pulled via `hcp_packer_artifact` - "no copy-pasted
modules slowly drifting apart." Point out the `prod` orchestration check
requiring manual approval - the policy/approval gate from the talk.

Approve/apply `dev` in the UI. Grab `public_ip` and `instance_id` from the
Stack's `dev` deployment → Outputs tab in the HCP Terraform UI (output
retrieval here is UI/API-driven, not a local `terraform output` command -
there's no local state file for a Stack deployment).

Open Infragraph in the HCP Terraform UI and show the new instance connected
to: its workspace, its AMI/Packer build, its deployment group. This is the
"ownership + policy + operational context in one graph" moment - the crux of
the talk.

## 3. Codify Day 2 ops (Terraform Actions + HCP Vault Dedicated + Ansible)

```bash
cd ../day2-rotation
terraform init
terraform apply -var="security_group_id=<sg id from dev output>"
```

The `cloud` block in `actions.tf` points this at workspace
`infragraph-demo-day2-rotation` in org `Devopstronaut` - `terraform init`
here authenticates to that workspace, and `terraform apply` creates a real,
visible run there (not local state). Because the workspace's Execution Mode
is set to Local, the plan/apply itself still runs on your laptop - so flip
over to the HCP Terraform UI during the apply and show the run streaming in
from your machine.

Narrate: this is a credential-rotation runbook that used to be a wiki page -
now it's a Terraform Action (`actions.tf`), version-controlled, peer-reviewed,
tracked as a run in HCP Terraform, and triggerable either automatically (on
an SG change) or on demand.

The `terraform_data.trigger_anchor` resource only fires the `after_update`
action_trigger when its tracked input actually changes (e.g. the SG's
`webapp_dev` data source resolves to a different value) - a no-op `apply`
won't refire it. For a reliable on-stage trigger, either invoke the action
directly from the HCP Terraform UI/CLI (if Actions-on-demand is enabled for
your org), or just run the underlying script directly:

```bash
../../scripts/rotate_credential.sh
```

Show:
1. HCP Vault now holds a freshly rotated credential - `source scripts/_vault_env.sh`
   then `vault kv get secret/infragraph-demo/dbcred` (or check it live in the
   HCP Vault UI)
2. Ansible pushed it to the target host (`/tmp/infragraph-demo-webapp/db-credential.env`
   on the dev instance, or localhost if you're running the safe default inventory)
3. Back in Infragraph: the Action run shows up attached to the same resource
   graph as the Stacks deployment - Day 2 ops now has the same ownership and
   audit trail as Day 1 provisioning.

## 4. Close the loop

Recap on the Infragraph graph view: one screen showing the shadow resource
(flagged, now either imported or flagged for cleanup), the standardized Stacks
deployment, the Packer image lineage, and the Day 2 Action run - "Day 2 or
never" because without this graph, each of those four things lives in a
different tool and nobody connects them until something breaks.

## 5. Teardown (do this right after, it's all real and billable)

```bash
cd ../../
./scripts/destroy.sh
```

This destroys the day2-rotation state and the **HCP Vault Dedicated
cluster** (the cluster bills hourly from creation, so don't let it sit
overnight) plus the out-of-band shadow resources. Then destroy the
`staging`/`prod` Stacks deployments from the HCP Terraform UI if you applied
them during rehearsal.
