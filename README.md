# day2-hcpinfragraph

A live-runnable demo for the talk **"Day 2 or Never: Closing the Multicloud Operations Gap
with HCP Terraform and Project Infragraph"** (TEC-4095). Migrating to the cloud was supposed to
simplify infrastructure. For most enterprises it didn't -- AWS, Azure, GCP, Kubernetes, and
hybrid environments grow faster than governance can keep up, leaving shadow infrastructure,
unclear ownership, drift, and fragmented Day 2 operations behind.

This repo walks through one real iteration of an **ILM (Infrastructure Lifecycle Management)
loop** against live AWS infra:

- **Surface** -- out-of-band AWS resources ("shadow IT") created with plain AWS CLI calls, no
  Terraform involved, then diffed against what HCP Terraform actually manages.
- **Govern** -- the standardized path everything *should* have gone through instead: a golden
  AMI built and registered by **HCP Packer**, with a `prod` deployment gated behind a manual
  approval check.
- **Standardise** -- one **Stacks** component (`webapp`) deployed identically into
  `dev` / `staging` / `prod` -- same module, same golden AMI, no copy-pasted modules slowly
  drifting apart.
- **Codify** -- a Day 2 credential-rotation runbook that used to be a wiki page, now a
  **Terraform Action** backed by **HCP Vault Dedicated** and **Ansible**, triggerable
  automatically on a security-group change or on demand.

**Project Infragraph** is the thread tying all four stages together: it connects the
infrastructure, its ownership, the policy that governed how it came to exist, and the
operational context of what's happened to it since -- into one graph instead of four
disconnected tools. That graph is also the stated foundation for agentic automation on top of
HCP Terraform, which is where the talk ends.

The demo is **presenter-driven** against a real AWS account and a real HCP Terraform
org -- not a sandboxed local-only walkthrough.

## Architecture

![Architecture diagram: GitHub repo connected to HCP Terraform (org Devopstronaut, Stacks + Workspaces + Infragraph graph), which pulls a golden AMI from HCP Packer and drives dev/staging/prod EC2 + Security Groups in AWS eu-west-1; HCP Vault Dedicated and Ansible rotate the webapp DB credential and push it to those instances; a separate untracked Shadow IT box (EC2, Security Group, S3) discovered live by Terraform Search (terraform query) and also surfaced in the Infragraph resource inventory](docs/images/architecture.png)

<details>
<summary>Mermaid source (text fallback)</summary>

```mermaid
flowchart TB
    subgraph HCPTF["HCP Terraform -- org: Devopstronaut"]
        Stack["Stacks\ncomponent: webapp\ndeployments: dev / staging / prod"]
        ActionWS["Workspace: infragraph-demo-day2-rotation\nExecution Mode: Local"]
        VaultWS["Workspace: infragraph-demo-vault"]
        Infragraph["Infragraph graph view\nowner + policy + ops context"]
    end

    Packer["HCP Packer registry\nbucket: infragraph-demo-webapp\nchannel: production"]
    Vault["HCP Vault Dedicated\ndev tier, public endpoint\nsecret/infragraph-demo/dbcred"]

    subgraph AWS["AWS account -- eu-west-1"]
        Shadow["Shadow IT\nshadow-reporting-service EC2\nshadow-reporting-sg\nS3 export bucket\n(created via AWS CLI, no Terraform)"]
        Dev["dev EC2 + SG\n(Stacks-managed)"]
        Staging["staging EC2 + SG\n(Stacks-managed)"]
        Prod["prod EC2 + SG\n(Stacks-managed)"]
    end

    Ansible["Ansible\nrotate_credential.yml"]

    Packer -->|hcp_packer_artifact\nexternal_identifier| Stack
    Stack --> Dev
    Stack --> Staging
    Stack --> Prod

    Dev -. "security_group_id\n(read-only data source)" .-> ActionWS
    ActionWS -->|after_update action_trigger\n(verified live) or direct script| Vault
    Vault -->|rotated credential| Ansible
    Ansible -->|pushes credential over SSH,\nreal httpd restart,\nrenders live dashboard| Dev

    VaultWS -.->|provisions + admin token| Vault

    Shadow -. "unmanaged -- no owning workspace" .-> Infragraph
    Stack -.-> Infragraph
    Packer -.-> Infragraph
    ActionWS -.-> Infragraph
```

</details>

Everything above is real: the EC2 instances, the security groups, the S3 bucket, the HCP Vault
Dedicated cluster (billed hourly from creation), and every HCP Terraform run. There is no local
mock of any of these pieces.

## The ILM loop, step by step

### 1. Surface the gap -- Terraform Search

```bash
./scripts/create_shadow_resources.sh
```

Creates a real EC2 instance (`shadow-reporting-service`), a security group open on 22/tcp to
`0.0.0.0/0`, and an S3 bucket -- all with plain AWS CLI calls, none of it in any Terraform
state. This is how most shadow IT is actually born: someone needed something fast.

Then run real Terraform Search (`terraform` 1.14+'s `list` blocks + `terraform query` --
distinct from, and not dependent on, Infragraph) against `terraform/search-shadow/`:

```bash
cd terraform/search-shadow
terraform init
terraform query                                            # discover it
terraform query -generate-config-out=generated_import.tf   # generate import + resource blocks
cd ../..
```

`shadow.tfquery.hcl`'s `list` block queries live AWS for running instances tagged
`Demo=tec4095-infragraph-shadow` -- the exact tag `create_shadow_resources.sh` leaves on
the shadow instance and nothing else. `terraform query` alone just discovers and prints it;
`-generate-config-out` is the "bulk import" half of the feature, producing an accurate
`aws_instance` resource block (AMI, subnet, SG, tags, everything) plus an `import` block
ready to bring it under Terraform management -- narrate this as the actual remediation step,
without necessarily running `terraform apply` on it during the talk (that would move it out
of `shadow_vs_managed_diff.sh`'s and `destroy.sh`'s AWS-CLI-tag-based cleanup path).

If you'd rather not touch real Terraform Search live, `shadow_vs_managed_diff.sh` is a local,
no-dependencies fallback that lists every running EC2 instance next to what the Stacks state
knows about and prints the gap:

```bash
./scripts/shadow_vs_managed_diff.sh
```

### 2. Standardise the real deployment -- HCP Packer + Stacks

```bash
./scripts/build_and_promote_image.sh
```

Builds the golden AMI with Packer and registers it in the HCP Packer registry under bucket
`infragraph-demo-webapp`. Promoting the build to the `production` channel is a deliberately
manual step, narrated live -- that's the moment the `hcp_packer_artifact` data source in
`terraform/stacks/components.tfcomponent.hcl` has something new to pick up.

The Stack itself (`terraform/stacks/`) has **no local-apply path** -- it's triggered from the
HCP Terraform UI against one component (`components/webapp`) and three deployments
(`deployments.tfdeploy.hcl`: `dev`, `staging`, `prod`). `dev`/`staging` sit in an
auto-approving `deployment_group`; `prod` is left out of it, so it falls back to HCP
Terraform's default manual-approval group -- the policy/approval gate from the talk,
scoped to just the environment that needs it.

### 3. Codify Day 2 ops -- Terraform Actions + HCP Vault Dedicated + Ansible

```bash
cd terraform/day2-rotation
terraform apply -var="security_group_id=<sg id from the dev deployment's output>"
```

`actions.tf` defines `action.local_command.rotate_db_credential`, wired two ways:

- **Automatically** -- a `terraform_data.trigger_anchor` resource reads the dev security
  group (read-only `data.aws_security_group.webapp_dev`) and fires the `after_update`
  `action_trigger` whenever that SG actually changes. Verified live: forcing the `webapp`
  SG to be replaced (see `aws_security_group.webapp`'s `lifecycle { create_before_destroy
  = true }` -- required, since without it AWS rejects deleting the old SG while an instance
  is still attached to it, and the whole apply fails) and re-applying `day2-rotation` with
  the new SG id genuinely fires the trigger -- the apply log shows `Action complete:
  action.local_command.rotate_db_credential (triggered by terraform_data.trigger_anchor)`.
- **On demand** -- in principle, invokable directly from the HCP Terraform UI/CLI if
  Actions-on-demand is enabled for your org. In practice, for *this* action, don't expect
  it to show up there even when it is: it only fires via the lifecycle trigger above, and
  empirically (tested against this org) a trigger-bound action stays absent from the
  workspace's Actions page/`terraform-actions` API regardless of execution mode or whether
  it has actually fired. The architecture is a dead end here anyway -- Actions-on-demand
  needing `remote` execution and this action needing `local` execution (to reach
  `ansible-playbook`, your SSH key, and local AWS/Vault creds) are mutually exclusive for
  this particular runbook. Treat the run log as the real proof, not the Actions UI. The
  always-available fallback is running the underlying runbook yourself:

```bash
./scripts/rotate_credential.sh
```

That script rotates the credential in HCP Vault Dedicated (`secret/infragraph-demo/dbcred`),
then hands off to Ansible (`ansible/rotate_credential.yml`) to push it to the target host and
restart the app. What used to be a wiki page is now version-controlled, peer-reviewed, and
tracked as a run in HCP Terraform.

By default `ansible/inventory.ini` targets `localhost` (safe default, runnable before AWS
creds/instances exist). For a genuinely live push -- Ansible connecting over real SSH to the
actual `dev`/`staging`/`prod` instances, rewriting each one's live page, and restarting
`httpd` for real -- the `webapp` module attaches an SSH keypair (`key_name`, default
`infragraph-demo-ssh`) and opens port 22 scoped to a `ssh_cidr` input (never `0.0.0.0/0` --
scope it to the presenter's own IP) on all three environments' security groups. List all
three real public IPs in `inventory.ini` locally (don't commit this -- it's instance-specific
and goes stale on every replacement) and re-run the script: each instance's page is a dark,
auto-refreshing (every 5s) dashboard showing the rotation timestamp and a masked credential
fingerprint -- refreshing the browsers mid-talk is the actual proof the same rotated
credential reached every running environment, not just Vault and a log line. Note this is a
deliberate widening of scope from the Terraform Action's *trigger*, which still only watches
the `dev` security group (`data.aws_security_group.webapp_dev` in `actions.tf`) -- the
rotation itself now fans out to all three, the trigger condition didn't change.

### 4. Close the loop

Back in the HCP Terraform UI, Infragraph's graph view is the payoff frame: the shadow resource
(now flagged, imported, or marked for cleanup), the standardized Stacks deployment, the Packer
image lineage behind it, and the Day 2 Action run -- all on one graph. "Day 2 or never" because
without that graph, each of those four things lives in a different tool and nobody connects
them until something breaks.

## Everything runs through HCP Terraform, not local state

This is a demo *for* HCP Terraform, so every piece's run history/state lives in the org, not on
your laptop:

- **Stacks** (`terraform/stacks/`) only run in HCP Terraform -- there's no local-apply path.
  Create the Stack in the HCP Terraform UI by connecting this repo and pointing it at
  `terraform/stacks/`; plans/applies for dev/staging/prod happen there, not via local
  `terraform` commands.
- **day2-rotation** (`terraform/day2-rotation/actions.tf`) uses a `cloud` block targeting
  workspace `infragraph-demo-day2-rotation` in org `Devopstronaut`, with **Execution Mode set
  to Local**: the Action shells out to `ansible-playbook`, which a remote HCP Terraform
  execution sandbox can't reach. Verified live: Local execution mode means HCP Terraform
  **does not track this as a Run** -- the Runs tab stays permanently empty for this
  workspace (`"total-count": 0` via the API, confirmed after several real applies), because
  Local mode is a pure state backend ("HCP Terraform only stores and synchronizes state," per
  the execution-mode picker's own description) -- it's not a UI bug, it's what the setting
  means. What *does* update is the **State** tab (new serial number per apply); the apply
  output itself only ever streams in your own terminal, not the web UI.
- **Vault** is HCP Vault Dedicated (`terraform/vault-hcp/`), not a local container -- a real,
  billed-hourly cluster provisioned by its own `cloud`-backed workspace
  (`infragraph-demo-vault`).
- **HCP Packer** registry push happens from wherever `packer build` runs (your laptop or CI) --
  the registry itself is HCP-hosted, so the image provenance Stacks consumes is already "in
  HCP."

## Prerequisites

- HCP Terraform org: **Devopstronaut** (workspace/stack prefix: `infragraph-demo`)
  - `terraform login` done locally (CLI-driven workspace auth)
  - Stack created in the UI, pointed at `terraform/stacks/`
  - Workspace `infragraph-demo-day2-rotation` created with Execution Mode = Local
  - Workspace `infragraph-demo-vault` created (any execution mode -- no local tool
    dependencies)
  - Workspace `infragraph-demo-search-shadow` created (remote execution; backs
    `terraform/search-shadow/` so Terraform Search runs show up in the HCP Terraform UI's
    Search & Import page, not just the local CLI)
  - **Put the Stack and all three workspaces in the same HCP Terraform project.** New
    workspaces/Stacks created without an explicit project land in whichever one is your
    org's default, and nothing stops them drifting apart later (a UI edit, a scripted
    `PATCH`) -- if they split across projects, a project-scoped variable set (like the one
    backing the Stack's `aws`/`hcp` provider credentials) silently stops covering the
    stragglers, and you'll lose track of which workspace is where.
- AWS CLI configured with credentials for the target account, region `eu-west-1` (check with
  `aws sts get-caller-identity` -- these need to be valid before running anything that touches
  real infra)
- `terraform` (**1.14+**, for `terraform query`/Terraform Search in `terraform/search-shadow/`),
  `packer`, `vault`, `ansible-playbook` CLIs installed
- HCP service principal credentials (`HCP_CLIENT_ID` / `HCP_CLIENT_SECRET`) -- used for both the
  HCP Packer registry push and the HCP Vault provider

## This stack costs real money while it's up

`create_shadow_resources.sh` and the Stacks `dev` deployment both create real AWS resources
(EC2 instances, security groups, an S3 bucket for shadow resources). `bootstrap_vault.sh`
provisions a real HCP Vault Dedicated cluster, billed hourly from the moment it's created.

**Run `scripts/destroy.sh` as soon as the demo/rehearsal is done.** It tears down the
day2-rotation state and the HCP Vault Dedicated cluster (priority teardown -- that's the one
billing hourly), then removes the tagged out-of-band shadow resources. The Stacks-managed
`staging`/`prod` deployments aren't covered by this script -- destroy those from the HCP
Terraform UI (Stacks -> destroy deployment) if you applied them during rehearsal.

## Layout

| Path | What's there |
|---|---|
| `terraform/stacks/` | The Stacks component (`components/webapp`: default VPC + SG + EC2) and the `dev`/`staging`/`prod` deployments, including the `prod`-only manual-approval orchestration check |
| `terraform/packer/` | `golden-ami.pkr.hcl` -- builds the AMI and registers it in the HCP Packer registry that Stacks consumes via `hcp_packer_artifact` |
| `terraform/day2-rotation/` | The Terraform Action (`actions.tf`) that rotates the DB credential -- auto-triggered on an SG change, or invoked on demand |
| `terraform/vault-hcp/` | HCP Vault Dedicated: HVN + cluster (dev tier, public endpoint) + admin token, backing the rotation runbook |
| `terraform/search-shadow/` | Real Terraform Search config (`shadow.tfquery.hcl`'s `list` block + `terraform query`) that discovers the shadow EC2 instance by tag and can generate import config for it |
| `ansible/rotate_credential.yml` | Pushes the rotated credential to every host in `inventory.ini`, renders a live auto-refreshing dashboard page on each, and does a real `httpd` restart; `inventory.ini` defaults to `localhost` so the playbook is runnable before AWS creds/instances exist |
| `scripts/create_shadow_resources.sh` | Creates the out-of-band "shadow IT" (EC2, SG, S3) that Terraform has never heard of |
| `scripts/shadow_vs_managed_diff.sh` | Local fallback for the Search/Infragraph gap demo -- diffs running EC2 instances against the Stacks state |
| `scripts/build_and_promote_image.sh` | Packer build + HCP Packer registry push (promotion to the `production` channel stays a manual, narrated step) |
| `scripts/bootstrap_vault.sh` | Provisions the HCP Vault Dedicated cluster and seeds the initial `secret/infragraph-demo/dbcred` credential |
| `scripts/rotate_credential.sh` | The actual Day 2 runbook -- rotates the Vault credential, then hands off to Ansible |
| `scripts/_vault_env.sh` | Shared helper: exports `VAULT_ADDR`/`VAULT_TOKEN`/`VAULT_NAMESPACE` from `terraform/vault-hcp`'s outputs |
| `scripts/destroy.sh` | Tears down the day2-rotation state, the HCP Vault cluster, and the tagged shadow resources |
| `docs/DEMO_SCRIPT.md` | Step-by-step narration for the live demo, staged against the sections above |

## Open risks

- `shadow_vs_managed_diff.sh` only diffs against local Stacks state (`terraform -chdir
  state list`) -- Stacks has no local state file by design, so this fallback only shows
  anything useful if run from a checkout that's actually applied the Stack locally at some
  point, or is swapped for pasted instance IDs from the HCP Terraform UI.
- The shadow security group (`shadow-reporting-sg`) opens port 22 to `0.0.0.0/0` on a real
  AWS account -- intentional for the demo narrative, but it's a real open security group for
  as long as it exists. `scripts/destroy.sh` removes it, but don't leave it up between
  rehearsals.
- `terraform/vault-hcp/outputs.tf`'s `admin_token` output is a cluster-admin Vault token,
  marked `sensitive` but still materialized into HCP Terraform state. Treat that workspace's
  state with the same care as any other secret-bearing state.
- `terraform_data.trigger_anchor`'s `after_update action_trigger` only fires when its tracked
  input (the SG data source) actually resolves to a new value -- a no-op `terraform apply`
  will not refire the rotation Action. To force a reliable on-stage firing, bump the SG's
  name in `terraform/stacks/components/webapp/main.tf` (e.g. `-sg-v2` -> `-sg-v3`) so AWS
  replaces it with a new id, push, approve the Stack apply, then re-apply `day2-rotation`
  with that new id -- or just run `scripts/rotate_credential.sh` directly, as called out in
  `docs/DEMO_SCRIPT.md`, which is the lower-ceremony option if you don't need the literal
  trigger-fired-by-an-SG-change moment on stage.
- `terraform query` in `terraform/search-shadow/` needs AWS provider `~> 6.0` -- the `aws_instance`
  list resource isn't supported on the `~> 5.0` pin used elsewhere in this repo (`terraform/stacks/`,
  `terraform/day2-rotation/`), so this directory's `.terraform.lock.hcl` deliberately differs
  from the rest.
- `terraform query -generate-config-out=generated_import.tf` is gitignored -- it's a
  point-in-time snapshot keyed to whatever shadow instance ID exists when you run it, and
  goes stale (wrong instance ID) the moment `destroy.sh`/`create_shadow_resources.sh` cycles.
- `webapp`'s `key_name` and `ssh_cidr` variables are baked in for the live-push demo path.
  `key_name` is an immutable `aws_instance` argument -- changing either value forces
  **all three** `dev`/`staging`/`prod` instances to be replaced (new instance IDs, new public
  IPs) on the next apply, not just a config update. If your presenter IP changes between
  rehearsal and the real talk, update `ssh_cidr` in `deployments.tfdeploy.hcl`, expect another
  replacement, and grab the new `dev` IP for `inventory.ini` again.
- The locally-edited `ansible/inventory.ini` (pointed at a real instance IP) should stay
  **uncommitted** -- it's specific to whichever instance is currently live and will be wrong
  the moment that instance gets replaced.
- `aws_security_group.webapp` needs `lifecycle { create_before_destroy = true }` -- without
  it, any change that forces the SG to be replaced (like the name) makes Terraform try to
  *destroy* the old SG before creating the new one, AWS rejects that with
  `DependencyViolation` (the instance is still attached), and the whole deployment fails
  without ever creating the replacement. Hit this for real forcing the trigger-firing test
  above; it's now fixed in the module, but worth remembering if you touch this resource
  again. With the fix, replacing the SG updates the instance's `vpc_security_group_ids`
  in-place -- the instance itself doesn't get replaced, only `key_name`/`ssh_cidr` changes
  force that.
- Workspace/project drift is real, not theoretical -- `infragraph-demo-day2-rotation` ended
  up in a different HCP Terraform project than the Stack and the other two workspaces partway
  through this demo's setup (cause unclear -- possibly a UI edit while exploring Actions
  settings). If something that used to work stops seeing credentials/variable sets, check
  each workspace's project assignment before assuming the config is wrong.
