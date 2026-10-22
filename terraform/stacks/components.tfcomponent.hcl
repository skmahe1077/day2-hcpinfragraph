# HCP Terraform Stacks - component definitions
# Org: Devopstronaut | Workspace/stack prefix: infragraph-demo
#
# This defines ONE standardized "webapp" pattern that gets deployed
# identically (same module, versioned together) into dev / staging / prod.
# This is the "standardise deployments with Stacks" part of the ILM loop.

required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
  hcp = {
    source  = "hashicorp/hcp"
    version = "~> 0.100"
  }
}

provider "aws" "this" {
  config {
    region = var.region
  }
}

provider "hcp" "this" {
  config {}
}

# Golden AMI published by the HCP Packer pipeline (see terraform/packer/).
# Pulling the "production" channel here is what links Packer provenance
# into the Infragraph graph: every deployment's AMI traces back to a
# specific Packer build + the source commit that produced it.
component "golden_ami" {
  source = "./components/golden_ami"

  inputs = {
    region = var.region
  }

  providers = {
    hcp = provider.hcp.this
  }
}

component "webapp" {
  source = "./components/webapp"

  inputs = {
    region        = var.region
    environment   = var.environment
    instance_type = var.instance_type
    ami_id        = component.golden_ami.external_identifier
    owner         = var.owner
  }

  providers = {
    aws = provider.aws.this
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "environment" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

output "instance_id" {
  type  = string
  value = component.webapp.instance_id
}

output "public_ip" {
  type  = string
  value = component.webapp.public_ip
}
