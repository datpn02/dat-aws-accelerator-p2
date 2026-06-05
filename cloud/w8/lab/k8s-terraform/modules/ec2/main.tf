# Tìm AMI Ubuntu 22.04 mới nhất tự động
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # ID chính thức của Canonical (công ty làm Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Security Group của EC2
# Cho phép ai vào port nào
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-kind-sg"
  description = "Security group for K8s on EC2"
  vpc_id      = var.vpc_id

  # ALB sẽ gửi traffic vào port 30080 (NodePort của K8s)
  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH để null_resource remote-exec kết nối vào
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Cho EC2 ra internet (để tải Docker, kind, kubectl...)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-kind-sg" }
}

# Tạo EC2
resource "aws_instance" "k8s" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium" # Tối thiểu: kind cần 2CPU + 2GB RAM
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  subnet_id              = var.subnet_id

  root_block_device {
    volume_size = 20   # 20GB đủ cho K8s images
    volume_type = "gp3"
  }

  # Script này chạy tự động khi EC2 khởi động lần đầu
  # Nó sẽ cài Docker, kind, kubectl, deploy app
  user_data = file("${path.module}/user_data.sh")

  tags = { Name = "k8s-terraform" }
}