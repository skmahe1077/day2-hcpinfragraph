# HCP Vault Dedicated for the Day 2 credential-rotation runbook.
# Real, billable cluster - the "dev" tier is the lowest-cost option and
# is intended for exactly this kind of short-lived demo use. Destroy it
# right after the talk (scripts/destroy.sh handles this).

terraform {
  cloud {
    organization = "Devopstronaut"
    workspaces {
      name = "infragraph-demo-vault"
    }
  }

  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.100"
    }
  }
}

provider "hcp" {}

resource "hcp_hvn" "demo" {
  hvn_id         = "infragraph-demo-hvn"
  cloud_provider = "aws"
  region         = var.region
  cidr_block     = "172.25.16.0/20"
}

resource "hcp_vault_cluster" "demo" {
  cluster_id = "infragraph-demo-vault"
  hvn_id     = hcp_hvn.demo.hvn_id
  tier       = "dev"

  # Public endpoint avoids needing HVN<->AWS VPC peering for the demo -
  # the EC2 instance and your laptop both reach Vault over the internet.
  # Access is still gated by the admin token below; this is a demo
  # shortcut, not a production pattern.
  public_endpoint = true
}

resource "hcp_vault_cluster_admin_token" "demo" {
  cluster_id = hcp_vault_cluster.demo.cluster_id
}
