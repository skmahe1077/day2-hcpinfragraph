# HCP Terraform Stacks - deployments
# Three deployments of the same component, same code, different inputs.
# This is what gives Infragraph a clean "one pattern, three environments"
# view instead of three hand-rolled, slowly-diverging copies.

deployment "dev" {
  inputs = {
    region        = "eu-west-1"
    environment   = "dev"
    instance_type = "t3.micro"
    owner         = "platform-team"
  }
}

deployment "staging" {
  inputs = {
    region        = "eu-west-1"
    environment   = "staging"
    instance_type = "t3.small"
    owner         = "platform-team"
  }
}

deployment "prod" {
  inputs = {
    region        = "eu-west-1"
    environment   = "prod"
    instance_type = "t3.medium"
    owner         = "platform-team"
  }
}

# Require an explicit approval before prod applies - this is the
# "policy and approval workflow" gate mentioned in the talk, scoped
# down to just prod for the demo.
orchestrate "auto_approve" "non_prod_only" {
  check {
    condition     = context.deployment.name != "prod"
    error_message = "prod requires manual approval"
  }
}
