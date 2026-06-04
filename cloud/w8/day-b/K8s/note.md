# W8 - Day B: Kubernetes Container/Orchestration

> Date: 02/06/2026

---

# Objectives

* Hiểu Container Orchestration.
* Hiểu kiến trúc Kubernetes.
* Hiểu Pod, Service, Probes.
* Hiểu ConfigMap và Secret.
* Hiểu NetworkPolicy.
* Cài đặt Docker Desktop, Minikube và kubectl.

---

# 1. Container Orchestration

## Vấn đề khi chỉ dùng Docker

Giả sử có:

* 10 containers
* 5 servers

Các vấn đề phát sinh:

* Container bị crash
* Scale thủ công
* Load balancing khó khăn
* Rolling update phức tạp
* Quản lý networking khó

Docker không giải quyết toàn bộ các vấn đề trên.

---

## Kubernetes

Kubernetes là hệ thống Container Orchestration giúp:

* Deploy tự động
* Scale tự động
* Self-healing
* Service Discovery
* Load Balancing
* Rolling Update / Rollback

```text
Developer
    |
 kubectl
    |
 Kubernetes API
    |
+------------------+
| Kubernetes       |
| Cluster          |
+------------------+
    |
  Pods
```

---

# 2. Kubernetes Architecture

## Control Plane

Điều khiển toàn bộ Cluster.

### API Server

Cổng giao tiếp chính.

```bash
kubectl get pods
```

Mọi request đều đi qua API Server.

---

### etcd

Database của Kubernetes.

Lưu:

* Pod
* Deployment
* Service
* Secret
* ConfigMap

---

### Scheduler

Chọn Node phù hợp để chạy Pod.

---

### Controller Manager

Đảm bảo trạng thái thực tế giống trạng thái mong muốn.

Ví dụ:

```text
Desired Pod = 3
Current Pod = 2

=> Kubernetes tạo thêm 1 Pod
```

---

## Worker Node

Nơi chạy workload.

Bao gồm:

* kubelet
* kube-proxy
* container runtime

---

# 3. Pod


Pod là đơn vị nhỏ nhất trong Kubernetes.

Một Pod chứa:

* Một hoặc nhiều containers
* Shared Network
* Shared Storage

Ví dụ:

```text
Pod
 └── nginx container
```

---

Tạo Pod

pod.yaml

```yaml
apiVersion: v1
kind: Pod

metadata:
  name: nginx-pod

spec:
  containers:
  - name: nginx
    image: nginx
```

Deploy:

```bash
kubectl apply -f pod.yaml
```

Kiểm tra:

```bash
kubectl get pods
```

---

# 4. Service


Pod có thể bị recreate.

IP của Pod thay đổi liên tục.

Service cung cấp endpoint ổn định.

```text
Client
   |
Service
   |
 Pods
```

---

## ClusterIP

Mặc định.

Chỉ truy cập bên trong cluster.

---

## NodePort

Expose service ra ngoài cluster.

Ví dụ:

```yaml
apiVersion: v1
kind: Service

metadata:
  name: nginx-service

spec:
  type: NodePort

  selector:
    app: nginx

  ports:
  - port: 80
    targetPort: 80
```

---

# 5. Probes

Probes giúp Kubernetes kiểm tra trạng thái ứng dụng.

---

## Liveness Probe

Kiểm tra ứng dụng còn sống không.

Nếu fail:

```text
Restart Container
```

Ví dụ:

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
```

---

## Readiness Probe

Kiểm tra ứng dụng đã sẵn sàng nhận traffic chưa.

Nếu fail:

```text
Không nhận traffic
```

Container vẫn chạy.

---

## Startup Probe

Dùng cho ứng dụng khởi động chậm.

Ví dụ:

```yaml
startupProbe:
  httpGet:
    path: /
    port: 80
```

---

# 6. ConfigMap

Lưu cấu hình không nhạy cảm.

Ví dụ:

```yaml
apiVersion: v1
kind: ConfigMap

metadata:
  name: app-config

data:
  APP_ENV: production
```

---

## Sử dụng ConfigMap

```yaml
env:
- name: APP_ENV
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: APP_ENV
```

---

# 7. Secret


Lưu dữ liệu nhạy cảm:

* Password
* API Key
* Token

Ví dụ:

```yaml
apiVersion: v1
kind: Secret

metadata:
  name: db-secret

type: Opaque

stringData:
  username: admin
  password: password123
```

---

## Khác nhau giữa ConfigMap và Secret

| ConfigMap           | Secret               |
| ------------------- | -------------------- |
| Config thường       | Dữ liệu nhạy cảm     |
| Plain text          | Base64 encoded       |
| Không chứa mật khẩu | Chứa mật khẩu, token |

---

# 8. NetworkPolicy

Firewall của Kubernetes.

Quy định:

* Pod nào được phép giao tiếp
* Pod nào bị chặn

---

Ví dụ:

```text
Frontend Pod
     |
     v
 Backend Pod

Allowed
```

```text
Unknown Pod
     |
     X
 Backend Pod

Blocked
```

---

Ví dụ NetworkPolicy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy

metadata:
  name: allow-frontend

spec:
  podSelector:
    matchLabels:
      app: backend

  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
```

---

# 9. Cài đặt môi trường

## Docker Desktop

Kiểm tra:

```bash
docker version
```

---

## kubectl

Kiểm tra:

```bash
kubectl version --client
```

---

## Minikube

Khởi động:

```bash
minikube start
```

Kiểm tra:

```bash
kubectl get nodes
```
