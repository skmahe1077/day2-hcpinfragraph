# Terraform Actions - codifies the Day 2 "rotate the webapp DB
# credential" runbook as a first-class, versioned, auditable unit
# instead of a wiki page someone runs by hand.
#
# Wired two ways for the demo:
#   1. Automatically: triggered whenever the webapp security group
#      changes (lifecycle action_trigger below) - "something changed,
#      so re-roll the credential."
#   2. On demand: run directly from the HCP Terraform UI/CLI as a
#      standalone action invocation - "the Day 2 runbook button."

terraform {
  cloud {
    organization = "Devopstronaut"
    workspaces {
      name = "infragraph-demo-day2-rotation"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

provider "aws" {
  region = var.region
}

variable "security_group_id" {
  description = "Security group ID from the Stacks webapp deployment (dev)"
  type        = string
}

action "local_command" "rotate_db_credential" {
  config {
    command   = "bash"
    arguments = ["${path.module}/../../scripts/rotate_credential.sh"]
  }
}

# Existing security group managed by the Stacks "dev" deployment.
# Referencing it here (read-only) is what lets this Action show up
# connected to that resource in the Infragraph graph.
data "aws_security_group" "webapp_dev" {
  id = var.security_group_id
}

resource "terraform_data" "trigger_anchor" {
  # Built-in resource (no provider/API calls) used purely as the
  # lifecycle anchor for the action_trigger below - keeps this module
  # decoupled from the Stacks state while still giving the Action
  # something to attach to, without touching the real SG's rules.
  input = data.aws_security_group.webapp_dev.id

  lifecycle {
    action_trigger {
      events  = [after_update]
      actions = [action.local_command.rotate_db_credential]
    }
  }
}
