output "public_ip" {
  description = "IP public của EC2"
  value       = aws_instance.k8s.public_ip
}

output "instance_id" {
  description = "ID của EC2 instance"
  value       = aws_instance.k8s.id
}