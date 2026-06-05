output "ec2_public_ip" {
  description = "IP của EC2"
  value       = module.ec2.public_ip
}

output "app_url" {
  description = "Mở URL này trên browser để xem app"
  value       = "http://${module.alb.alb_dns_name}"
}

output "ssh_command" {
  description = "Lệnh SSH vào EC2 nếu cần debug"
  value       = "ssh -i ${var.private_key_path} ubuntu@${module.ec2.public_ip}"
}