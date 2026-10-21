locals {
  name = "infragraph-demo-${var.environment}"

  tags = {
    Name        = local.name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "hcp-terraform-stacks"
    Demo        = "tec4095-infragraph"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "webapp" {
  name        = "${local.name}-sg"
  description = "Standardized webapp SG issued by Stacks - ${var.environment}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_instance" "webapp" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.webapp.id]

  tags = local.tags
}
