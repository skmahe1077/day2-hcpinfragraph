# Real Terraform Search (Terraform 1.14+ `list` blocks / `terraform query`),
# not just Infragraph's resource inventory. Finds the untracked
# "shadow IT" EC2 instance created by scripts/create_shadow_resources.sh
# by the tag it was deliberately left with, and nothing else -
# demonstrating the "discover ungoverned resources" half of the talk for
# real, live, on stage.
#
# Run:
#   terraform init
#   terraform query
#   terraform query -generate-config-out=generated_import.tf   # to produce import + resource blocks
list "aws_instance" "shadow" {
  provider = aws

  config {
    filter {
      name   = "tag:Demo"
      values = ["tec4095-infragraph-shadow"]
    }
    filter {
      name   = "instance-state-name"
      values = ["running"]
    }
  }
}
