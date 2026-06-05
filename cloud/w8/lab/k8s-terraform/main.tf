# Lấy default VPC (có sẵn trên mọi AWS account, không cần tạo mới)
data "aws_vpc" "default" {
  default = true
}

# Lấy danh sách subnet trong default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Tạo EC2 + K8s bên trong
module "ec2" {
  source           = "./modules/ec2"
  key_name         = var.key_name
  vpc_id           = data.aws_vpc.default.id
  subnet_id        = tolist(data.aws_subnets.default.ids)[0]
}

# null_resource: dùng provider "null" để SSH vào EC2
# Mục đích: chờ K8s + app thực sự chạy xong rồi mới tạo ALB
# Nếu không có bước này → ALB tạo quá sớm → health check fail
resource "null_resource" "wait_for_k8s" {
  depends_on = [module.ec2]

  connection {
    type        = "ssh"
    host        = module.ec2.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Dang cho K8s khoi dong...'",
      "timeout 600 bash -c 'until [ -f /tmp/k8s-ready ]; do sleep 15; echo still waiting...; done'",
      "echo 'K8s da san sang!'",
      "sudo -u ubuntu KUBECONFIG=/home/ubuntu/.kube/config kubectl get nodes",
      "sudo -u ubuntu KUBECONFIG=/home/ubuntu/.kube/config kubectl get pods -A",
      "curl -sf http://localhost:30080 > /dev/null && echo 'App OK'"
    ]
  }
}

# Tạo ALB - CHỈ sau khi K8s đã sẵn sàng
module "alb" {
  source          = "./modules/alb"
  vpc_id          = data.aws_vpc.default.id
  ec2_instance_id = module.ec2.instance_id
  depends_on      = [null_resource.wait_for_k8s]
}