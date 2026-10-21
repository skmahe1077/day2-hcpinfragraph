# HCP Packer - builds the "golden AMI" consumed by the Stacks webapp
# component (terraform/stacks/components.tfcomponent.hcl). Registering
# the build in the HCP Packer registry is what lets Infragraph draw the
# line from "this running EC2 instance" back to "this exact Packer build,
# this exact base image, this exact commit."

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.3"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

source "amazon-ebs" "webapp" {
  ami_name      = "infragraph-demo-webapp-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"] # Amazon
    most_recent = true
  }

  ssh_username = "ec2-user"

  tags = {
    Name      = "infragraph-demo-webapp"
    ManagedBy = "hcp-packer"
    Demo      = "tec4095-infragraph"
  }
}

build {
  name    = "webapp"
  sources = ["source.amazon-ebs.webapp"]

  provisioner "shell" {
    inline = [
      "sudo dnf install -y httpd",
      "sudo systemctl enable httpd",
      "echo '<h1>infragraph-demo webapp - built by HCP Packer</h1>' | sudo tee /var/www/html/index.html"
    ]
  }

  hcp_packer_registry {
    bucket_name = "infragraph-demo-webapp"

    bucket_labels = {
      "demo"   = "tec4095-infragraph"
      "owner"  = "platform-team"
    }

    build_labels = {
      "build-time" = timestamp()
    }
  }
}
