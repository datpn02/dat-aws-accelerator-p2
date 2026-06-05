variable "vpc_id" {
  description = "ID của VPC"
  type        = string
}

variable "ec2_instance_id" {
  description = "ID của EC2 instance để ALB forward traffic vào"
  type        = string
}