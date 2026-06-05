variable "aws_region" {
  description = "AWS region để deploy"
}

variable "key_name" {
  description = "Tên EC2 Key Pair đã tạo trên AWS console"
  type        = string
}

variable "private_key_path" {
  description = "Đường dẫn tới file private key (.pem) dùng để SSH vào EC2 instance"
  type        = string
}