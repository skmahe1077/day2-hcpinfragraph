output "instance_id" {
  value = aws_instance.webapp.id
}

output "public_ip" {
  value = aws_instance.webapp.public_ip
}

output "security_group_id" {
  value = aws_security_group.webapp.id
}
