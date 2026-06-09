output "web_server_ip" {
  value = module.ec2.instance_public_ip
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "static_assets_bucket" {
  value = module.s3.bucket_name
}