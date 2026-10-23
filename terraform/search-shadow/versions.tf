terraform {
  cloud {
    organization = "Devopstronaut"
    workspaces {
      name = "infragraph-demo-search-shadow"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}
