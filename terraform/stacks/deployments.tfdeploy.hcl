# HCP Terraform Stacks - deployments
# Three deployments of the same component, same code, different inputs.
# This is what gives Infragraph a clean "one pattern, three environments"
# view instead of three hand-rolled, slowly-diverging copies.

# Require an explicit approval before prod applies - this is the
# "policy and approval workflow" gate mentioned in the talk, scoped
# down to just prod for the demo. dev/staging are placed in the
# "non_prod" deployment group below, which always auto-approves; prod
# is left out of that group, so HCP Terraform falls back to its
# default (manual-approval) group for it.
deployment_auto_approve "non_prod" {
  check {
    condition = true
    reason    = "non-prod deployments auto-approve"
  }
}

deployment_group "non_prod" {
  auto_approve_checks = [deployment_auto_approve.non_prod]
}

deployment "dev" {
  inputs = {
    region        = "eu-west-1"
    environment   = "dev"
    instance_type = "t3.micro"
    owner         = "platform-team"
  }
  deployment_group = deployment_group.non_prod
}

deployment "staging" {
  inputs = {
    region        = "eu-west-1"
    environment   = "staging"
    instance_type = "t3.small"
    owner         = "platform-team"
  }
  deployment_group = deployment_group.non_prod
}

deployment "prod" {
  inputs = {
    region        = "eu-west-1"
    environment   = "prod"
    instance_type = "t3.medium"
    owner         = "platform-team"
  }
}
