# Lấy tất cả subnet public trong VPC (ALB cần ít nhất 2 subnet, 2 AZ khác nhau)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# Security Group cho ALB: cho phép internet vào port 80
resource "aws_security_group" "alb_sg" {
  name   = "k8s-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Tạo ALB
resource "aws_lb" "main" {
  name               = "k8s-kind-alb"
  internal           = false          # public, internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.public.ids

  tags = { Name = "k8s-kind-alb" }
}

# Target Group: ALB sẽ gửi traffic đến EC2 qua port 30080
resource "aws_lb_target_group" "app" {
  name        = "k8s-app-tg"
  port        = 30080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    port                = "30080"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }
}

# Listener: ALB lắng nghe port 80, forward vào target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Gắn EC2 vào target group
resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = var.ec2_instance_id
  port             = 30080
}