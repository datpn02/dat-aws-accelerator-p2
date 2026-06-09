resource "aws_security_group" "db_sg" {
  name        = "${var.environment}-db-sg"
  description = "Allow MySQL only from web server"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from web server"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.web_sg_id]   # chỉ EC2 mới được kết nối
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-db-sg"
    Environment = var.environment
  }
}

# RDS cần subnet group có ít nhất 2 AZ
resource "aws_subnet" "private_b" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-southeast-1c"

  tags = {
    Name = "${var.environment}-private-subnet-b"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = [var.private_subnet_id, aws_subnet.private_b.id]

  tags = {
    Name        = "${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = "${var.environment}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "appdb"
  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  publicly_accessible = false   # QUAN TRỌNG: không expose ra internet
  skip_final_snapshot = true    # cho phép destroy không cần snapshot

  tags = {
    Name        = "${var.environment}-mysql"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}