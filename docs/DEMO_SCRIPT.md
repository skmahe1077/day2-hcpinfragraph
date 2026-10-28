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
- Workspace **`infragraph-demo-search-shadow`** created, remote execution (backs
  `terraform/search-shadow/` - without this, `terraform query` only runs as a local CLI
  command and nothing shows up in HCP Terraform's Search & Import UI page).
- `terraform/packer` built+promoted at least once (`scripts/build_and_promote_image.sh`)
  so a "production" AMI channel exists before the Stacks apply.
- **Double-check all three workspaces and the Stack are in the same HCP Terraform
  project.** This drifted mid-rehearsal once already - `infragraph-demo-day2-rotation` ended
  up in a different project than the others, and the symptom was confusing ("the workspace
  isn't even showing up") rather than an obvious error. Settings → General on each workspace
  shows its project.

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

### Enable the real Day 2 push (one-time, optional but worth it)

By default `rotate_credential.sh` only writes to `localhost` - safe, but it means the
"proof" of the rotation is just a log line. For a genuinely live push to all three real
instances:

1. `aws ec2 create-key-pair --key-name infragraph-demo-ssh --region eu-west-1
   --query 'KeyMaterial' --output text > ~/.ssh/infragraph-demo-ssh.pem && chmod 600
   ~/.ssh/infragraph-demo-ssh.pem` - the golden AMI's own build-time keypair is deleted by
   Packer after the build, so a new persistent one is needed for Ansible to connect.
2. In `deployments.tfdeploy.hcl`, set `ssh_cidr` on each deployment to **your current
   public IP** as a `/32` (`curl -s https://checkip.amazonaws.com`) - never
   `0.0.0.0/0`, that's exactly the insecure pattern the shadow-IT SG demonstrates.
   `key_name` (default `infragraph-demo-ssh`) and `ssh_cidr` are both set on the
   `webapp` module's `aws_instance`/security group, applied to all three environments.
   Push the change - `key_name` is immutable on `aws_instance`, so **this replaces all
   three** `dev`/`staging`/`prod` instances (new IDs, new public IPs) on the Stack's next
   apply.
3. List all three real public IPs in `ansible/inventory.ini` locally, e.g.:
   ```
   [webapp]
   <dev public ip> ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/infragraph-demo-ssh.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
   <staging public ip> ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/infragraph-demo-ssh.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
   <prod public ip> ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/infragraph-demo-ssh.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
   ```
   Keep this **uncommitted** - it's tied to whichever instances are live right now and goes
   stale the moment any of them get replaced (new rehearsal, IP changed, etc.). This is a
   deliberate scope widening beyond the Terraform Action's *trigger*, which still only
   watches the `dev` security group - the rotation itself now fans out to all three, the
   trigger condition in `actions.tf` didn't change.
4. Run `./scripts/rotate_credential.sh` - Ansible now connects over real SSH to all three
   hosts, rewrites each one's `/var/www/html/index.html` with a dark auto-refreshing
   dashboard (rotation timestamp + masked credential fingerprint, refreshes every 5s, real
   `Cache-Control: no-store` header so browsers can't mask the update with a stale cache),
   and does a real `systemctl restart httpd` on each. No Packer rebuild needed for this -
   httpd just serves whatever Ansible put on disk; the base AMI doesn't change.

Have `http://<dev public ip>/`, `http://<staging public ip>/`, and
`http://<prod public ip>/` open in three browser tabs **before** you start step 3 live -
since each page auto-refreshes, you don't even need to touch the browsers after running
the script on stage; all three update in sync.

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

## 1. Surface the gap (Terraform Search)

```bash
./scripts/create_shadow_resources.sh
```

This creates a real EC2 instance, security group, and S3 bucket **outside**
Terraform entirely - plain AWS CLI calls. Narrate: "this is how most shadow IT
is born - someone needed something fast."

Then run real Terraform Search - this is Terraform 1.14+'s `list` blocks and
`terraform query` CLI command, a distinct GA feature from Infragraph (it doesn't
need Infragraph activated/connected at all, just a recent Terraform CLI):

```bash
cd terraform/search-shadow
terraform init
terraform query
```

Narrate while it runs: this queries **live AWS**, right now, for anything tagged
the way `create_shadow_resources.sh` tagged the shadow instance - it comes back
with exactly `shadow-reporting-service` and nothing else, found with zero manual
console clicking. Then show the other half of the feature - generating real
import code for it:

```bash
terraform query -generate-config-out=generated_import.tf
cat generated_import.tf
```

Point at the generated `resource "aws_instance"` block (real AMI, subnet,
security group, tags - all pulled live) and the `import` block under it: "this
is the output - review it, drop it into your config, `terraform apply`, and
that shadow resource is governed." Don't actually run that apply live unless
you want to - it would also need `destroy.sh`'s shadow-resource cleanup path
reworked, since that currently deletes by AWS tag, not Terraform state.

**If you do want to actually `terraform plan`/`apply` the generated file**: the
AWS provider's generated config isn't always directly valid - it can emit
mutually-exclusive computed arguments together. The two conflicts we hit:
`ipv6_address_count` vs `ipv6_addresses` (delete the `ipv6_address_count`
line), and the `primary_network_interface { ... }` block vs
`associate_public_ip_address` (delete the whole `primary_network_interface`
block). Both are narration-worthy as-is - "generated config is a starting
point, review before you trust it" is a fair point to make live - but if you
want a clean `terraform plan` on stage, make those two edits first.
`cd ../..` back to the repo root when done.

If you'd rather not touch real Terraform Search live, `shadow_vs_managed_diff.sh`
is a local, no-dependencies fallback:

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
here authenticates to that workspace. **Correction, verified live**: with
Execution Mode = Local, HCP Terraform doesn't track this as a Run at all -
"Local" means it's a pure state backend (the project settings page says so
outright: "HCP Terraform only stores and synchronizes state"), so there's
nothing streaming to the UI and no entry in the workspace's Runs tab,
ever, by design - not a bug, not something to troubleshoot on stage. Don't
narrate "watch this show up in the HCP Terraform UI" for this apply. What
genuinely does update in HCP Terraform is the **State** tab (the
`terraform_data.trigger_anchor` resource's state, new serial number each
apply) - that's the one honest "this really talked to HCP Terraform" proof
point available here. The actual visible apply output is what's already
streaming in your own terminal; that's the real narration surface for this
step, not the web UI.

Narrate: this is a credential-rotation runbook that used to be a wiki page -
now it's a Terraform Action (`actions.tf`), version-controlled, peer-reviewed,
tracked as a run in HCP Terraform, and triggerable automatically on an SG
change - verified live: this genuinely fires. The apply log shows `Action
complete: action.local_command.rotate_db_credential (triggered by
terraform_data.trigger_anchor)`.

The `terraform_data.trigger_anchor` resource only fires the `after_update`
action_trigger when its tracked input actually changes (e.g. the SG's
`webapp_dev` data source resolves to a different value) - a no-op `apply`
won't refire it. Three ways to demo it, in order of how much ceremony you want:

- **The real trigger, on purpose**: bump the SG's name in
  `terraform/stacks/components/webapp/main.tf` (`-sg-v2` -> `-sg-v3`, etc.) -
  this forces AWS to replace the SG (new id), push, approve the Stack's
  apply (dev/staging auto-approve, prod needs the click), grab the new dev
  SG id, then `terraform apply -var="security_group_id=<new id>"` here. That
  apply is what genuinely fires the trigger - it's a heavier lift (another
  live infra change mid-talk) but it's the actual mechanism, not a
  substitute for it.
- **On-demand via Terraform's own CLI** (recommended default for stage) -
  `-invoke` is a first-class, documented Terraform feature, distinct from
  both the lifecycle trigger and from just calling the bash script
  yourself. It skips planning/applying everything else in the config and
  runs only the named action:

```bash
terraform apply -invoke=action.local_command.rotate_db_credential \
  -var="security_group_id=<dev sg id>" -auto-approve
```

  The apply log clearly labels it `Action started:
  action.local_command.rotate_db_credential (triggered by CLI)` - a clean
  "yes, I'm deliberately invoking this Day 2 action right now" moment
  without needing to replace real infrastructure first.
- **Lower-ceremony fallback**: just run the underlying script directly -
  identical end result (Vault rotation + Ansible push), useful if you don't
  want to type out the full `-invoke` address on stage:

```bash
../../scripts/rotate_credential.sh
```

Don't bother hunting for this action in the workspace's Actions page or
trying "Actions-on-demand" from the UI - tested directly against this org
(trigger-fired, CLI `-invoke`-fired, local execution, remote execution, all
four combinations) and it never shows up there. The architecture is a dead
end for this specific action anyway: the Actions
page's on-demand invocation needs `remote` execution, but this action needs
`local` execution to reach `ansible-playbook`/your SSH key/local AWS+Vault
creds - mutually exclusive requirements for this one runbook. The apply log
(either path above) is the real, reliable proof - don't promise the
audience an Actions-tab moment that isn't there.

Show, in order:
1. **HCP Vault** now holds a freshly rotated credential - `source scripts/_vault_env.sh`
   then `vault kv get secret/infragraph-demo/dbcred` (or check it live in the
   HCP Vault UI).
2. **The live pages** - flip to the three browser tabs already open on the `dev`,
   `staging`, and `prod` public IPs (see "Enable the real Day 2 push" above). Each
   auto-refreshes every 5s, so the rotation timestamp and masked credential fingerprint
   update on their own, in sync across all three, within seconds of the script finishing -
   no need to touch any browser. This is the actual payoff: one real credential rotated in
   a real Vault cluster, pushed over real SSH, and reflected identically on every running
   environment. (If you're on the `localhost` safe-default inventory instead, narrate the
   equivalent local file write at `/tmp/infragraph-demo-webapp/db-credential.env`.)
3. Back in Infragraph: the Action's definition and the `day2-rotation` workspace's
   `terraform apply` run are visible on the graph attached to the same resources as the
   Stacks deployment - Day 2 ops now has the same ownership and audit trail as Day 1
   provisioning.

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
overnight) plus the out-of-band shadow resources. It does not touch the
Stacks-managed `dev`/`staging`/`prod` deployments.

**The HCP Terraform UI can no longer destroy a Stack deployment directly**
(this changed 2026-04-04). The current way: add `destroy = true` to each
`deployment` block in `terraform/stacks/deployments.tfdeploy.hcl`, commit,
and push. `dev`/`staging` auto-approve (the `non_prod` deployment group);
`prod` still needs manual approval like a normal apply. Destroy **every**
deployment (`dev` included, not just `staging`/`prod`) **in that order,
before touching the Stack object itself** - deleting the Stack first does
not destroy its deployments, it just deletes the thing that was tracking
them, leaving the real `dev`/`staging`/`prod` EC2 instances and security
groups orphaned (no Stack, no state, nothing managing them) and still
running/billing.

Hit a second version of this failure for real: pushing the `destroy = true`
commit made the Stack vanish from the org entirely (404 on the Stack ID,
empty on the org's stacks list) within seconds - before any destroy run
could be confirmed complete. The org audit-trail API came back with zero
events for that window and the GitHub webhook delivery log only showed a
generic ack, so there was no way to retrieve what actually happened inside
HCP Terraform. Same orphaned-EC2-instances outcome either way, and the same
fix: find the instances and security groups by ID via `aws ec2
describe-instances`/`describe-security-groups` and remove them by hand
(`terminate-instances`, then `delete-security-group` once each instance
shows `terminated`).

**Always verify against AWS directly after any Stack teardown step** -
don't trust the Stack's own UI/API state as proof the real resources are
gone. The two can and did diverge.
