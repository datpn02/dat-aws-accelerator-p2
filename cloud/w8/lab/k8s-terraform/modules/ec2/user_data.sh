#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

# ── 1. Cài Docker ──────────────────────────────────────────────
apt-get update -y
apt-get install -y docker.io curl
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# ── 2. Cài kubectl ─────────────────────────────────────────────
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -Lo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# ── 3. Cài kind ────────────────────────────────────────────────
curl -Lo /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64"
chmod +x /usr/local/bin/kind

# ── 4. Tạo K8s cluster với kind ────────────────────────────────
# extraPortMappings: map port 30080 từ bên trong kind ra EC2 host
# Đây là lý do kind đơn giản hơn minikube: không cần socat
cat > /tmp/kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 30080
        protocol: TCP
EOF

sudo -u ubuntu bash << 'KIND_START'
  export HOME=/home/ubuntu
  kind create cluster --config /tmp/kind-config.yaml --wait 120s
  kubectl cluster-info
  kubectl get nodes
KIND_START

# ── 5. Deploy Nginx vào K8s ────────────────────────────────────
sudo -u ubuntu bash << 'DEPLOY'
  export HOME=/home/ubuntu
  export KUBECONFIG=/home/ubuntu/.kube/config

  # Tạo Deployment: chạy 2 pod nginx
  kubectl create deployment nginx-app \
    --image=nginx:alpine \
    --replicas=2

  # Expose ra NodePort cố định 30080
  kubectl expose deployment nginx-app \
    --type=NodePort \
    --port=80 \
    --target-port=80

  kubectl patch service nginx-app \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'

  # Chờ pod running
  kubectl rollout status deployment/nginx-app --timeout=120s
  kubectl get pods,svc
DEPLOY

# ── 6. Báo hiệu hoàn thành ─────────────────────────────────────
# null_resource trong main.tf chờ file này xuất hiện
echo "READY" > /tmp/k8s-ready
echo "Hoan thanh! K8s + app da chay"