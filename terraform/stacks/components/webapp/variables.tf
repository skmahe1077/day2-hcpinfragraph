variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type = string
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "key_name" {
  description = "EC2 keypair name for SSH access (Day 2 ops demo: Ansible needs to reach the real instance)"
  type        = string
  default     = "infragraph-demo-ssh"
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH in - scope this to the presenter's IP, never 0.0.0.0/0"
  type        = string
}
