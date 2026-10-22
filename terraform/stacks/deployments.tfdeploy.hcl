# HCP Terraform Stacks - deployments
# Three deployments of the same component, same code, different inputs.
# This is what gives Infragraph a clean "one pattern, three environments"
# view instead of three hand-rolled, slowly-diverging copies.

# Pulls the AWS + HCP service principal credentials from the
# "infragraph-demo-provider-creds" variable set (applied to this
# Stack's project) so the aws/hcp provider blocks in
# components.tfcomponent.hcl have something to authenticate with.
# Stacks don't inherit a workspace's ambient process environment the
# way classic workspaces do - values have to be read via `store` and
# wired through as explicit deployment inputs.
store "varset" "provider_creds" {
  name     = "infragraph-demo-provider-creds"
  category = "env"
}

# Require an explicit approval before prod applies - this is the
# "policy and approval workflow" gate mentioned in the talk, scoped
# down to just prod for the demo. dev/staging are placed in the
# "non_prod" deployment group below, which always auto-approves; prod
# is left out of that group, so HCP Terraform falls back to its
# default (manual-approval) group for it.
deployment_auto_approve "non_prod" {
  check {
    condition = context.plan.applyable
    reason    = "non-prod deployments auto-approve any valid plan"
  }
}

deployment_group "non_prod" {
  auto_approve_checks = [deployment_auto_approve.non_prod]
}

deployment "dev" {
  inputs = {
    region                 = "eu-west-1"
    environment            = "dev"
    instance_type          = "t3.micro"
    owner                  = "platform-team"
    ssh_cidr               = "82.33.90.77/32"
    aws_access_key_id      = store.varset.provider_creds.AWS_ACCESS_KEY_ID
    aws_secret_access_key  = store.varset.provider_creds.AWS_SECRET_ACCESS_KEY
    hcp_client_id          = store.varset.provider_creds.HCP_CLIENT_ID
    hcp_client_secret      = store.varset.provider_creds.HCP_CLIENT_SECRET
  }
  deployment_group = deployment_group.non_prod
}

deployment "staging" {
  inputs = {
    region                 = "eu-west-1"
    environment            = "staging"
    instance_type          = "t3.small"
    owner                  = "platform-team"
    ssh_cidr               = "82.33.90.77/32"
    aws_access_key_id      = store.varset.provider_creds.AWS_ACCESS_KEY_ID
    aws_secret_access_key  = store.varset.provider_creds.AWS_SECRET_ACCESS_KEY
    hcp_client_id          = store.varset.provider_creds.HCP_CLIENT_ID
    hcp_client_secret      = store.varset.provider_creds.HCP_CLIENT_SECRET
  }
  deployment_group = deployment_group.non_prod
}

deployment "prod" {
  inputs = {
    region                 = "eu-west-1"
    environment            = "prod"
    instance_type          = "t3.medium"
    owner                  = "platform-team"
    ssh_cidr               = "82.33.90.77/32"
    aws_access_key_id      = store.varset.provider_creds.AWS_ACCESS_KEY_ID
    aws_secret_access_key  = store.varset.provider_creds.AWS_SECRET_ACCESS_KEY
    hcp_client_id          = store.varset.provider_creds.HCP_CLIENT_ID
    hcp_client_secret      = store.varset.provider_creds.HCP_CLIENT_SECRET
  }
}
