variable "vpc_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "web_sg_id" {
  type        = string
  description = "Security group của EC2, cho phép kết nối vào RDS"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "environment" {
  type = string
}