variable "ami_id" {
  type        = string
  description = "AMI Ubuntu 22.04 ap-southeast-1"
  default     = "ami-0df7a207adb9748c7"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "subnet_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "environment" {
  type = string
}