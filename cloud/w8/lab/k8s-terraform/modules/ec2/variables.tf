variable "vpc_id" {
  description = "ID của VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID của subnet để đặt EC2"
  type        = string
}

variable "key_name" {
  description = "Tên Key Pair để SSH"
  type        = string
}