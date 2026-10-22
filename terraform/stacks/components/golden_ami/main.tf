# Golden AMI published by the HCP Packer pipeline (see terraform/packer/).
# Pulling the "production" channel here is what links Packer provenance
# into the Infragraph graph: every deployment's AMI traces back to a
# specific Packer build + the source commit that produced it.
data "hcp_packer_artifact" "golden_ami" {
  bucket_name  = var.bucket_name
  channel_name = var.channel_name
  platform     = "aws"
  region       = var.region
}
