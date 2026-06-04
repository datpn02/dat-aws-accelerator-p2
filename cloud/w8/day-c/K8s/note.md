# W8 - Day C: Kubernetes Scaling & Networking

> Date: 03/06/2026
> Focus: Deep dive Kubernetes + thực hành scaling, networking, expose services trên Minikube

---

# Learning Objectives

Sau Day-C, tôi có thể:

* Hiểu sâu cách Kubernetes schedule và scale workload
* Phân biệt các loại scaling (manual vs auto)
* Hiểu networking trong cluster (Service, NodePort, ClusterIP)
* Expose application từ cluster ra ngoài
* Debug basic Kubernetes resources
* Build mini platform trên Minikube

---

# 1. Recap Kubernetes Core

Kubernetes là hệ thống orchestration giúp:

* Deploy application dạng Pod
* Tự động restart khi lỗi (self-healing)
* Scale số lượng instance
* Quản lý networking giữa services

```text id="k8s-flow"
User
  ↓
Service
  ↓
Deployment
  ↓
ReplicaSet
  ↓
Pod
  ↓
Container
```

---

# 2. Scaling trong Kubernetes

## 2.1 Manual Scaling

Tăng số lượng Pod thủ công:

```bash id="scale1"
kubectl scale deployment nginx --replicas=3
```

Kiểm tra:

```bash id="scale2"
kubectl get pods
```

👉 Kubernetes sẽ đảm bảo luôn có đúng 3 Pod chạy.

---

## 2.2 Auto Scaling (HPA - Horizontal Pod Autoscaler)

Kubernetes tự scale dựa trên CPU/RAM.

Ví dụ:

```bash id="hpa1"
kubectl autoscale deployment nginx \
  --cpu-percent=50 \
  --min=1 \
  --max=5
```

Ý nghĩa:

* CPU > 50% → tăng Pod
* CPU thấp → giảm Pod

---

## 2.3 Khi nào dùng scaling?

| Case             | Type          |
| ---------------- | ------------- |
| Test nhanh       | Manual        |
| Production       | Auto Scaling  |
| High traffic app | HPA + metrics |

---

# 3. Kubernetes Networking

## 3.1 Pod Networking

Mỗi Pod có:

* IP riêng
* Giao tiếp nội bộ cluster

👉 Nhưng IP Pod thay đổi liên tục → không dùng trực tiếp

---

## 3.2 Service là gì?

Service = lớp abstraction để giữ IP cố định

```text id="svc1"
Client → Service → Pods
```

---

## 3.3 ClusterIP (default)

* Chỉ truy cập nội bộ cluster
* Dùng giữa backend services

```yaml id="clusterip"
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
    - port: 80
      targetPort: 8080
```

---

## 3.4 NodePort

Expose service ra ngoài node:

```yaml id="nodeport"
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
      nodePort: 30007
```

Truy cập:

```text id="access"
http://<node-ip>:30007
```

---

## 3.5 LoadBalancer (cloud)

* AWS / Azure / GCP hỗ trợ
* Tạo public IP tự động

---

# 4. Probes (Health Check)

## 4.1 Liveness Probe

Nếu fail → restart container

```yaml id="live"
livenessProbe:
  httpGet:
    path: /
    port: 80
```

---

## 4.2 Readiness Probe

Nếu fail → không nhận traffic

---

## 4.3 Startup Probe

Dành cho app startup chậm

---

# 5. ConfigMap & Secret (Config Management)

## ConfigMap

```yaml id="config"
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  ENV: production
```

---

## Secret

```yaml id="secret"
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  username: admin
  password: admin123
```

---

# 6. Lab: Mini Kubernetes Platform (Minikube)

## Step 1: Start cluster

```bash id="mk1"
minikube start
```

---

## Step 2: Check nodes

```bash id="mk2"
kubectl get nodes
```

---

## Step 3: Deploy app

```bash id="mk3"
kubectl create deployment nginx --image=nginx
```

---

## Step 4: Scale app

```bash id="mk4"
kubectl scale deployment nginx --replicas=3
```

---

## Step 5: Expose service

```bash id="mk5"
kubectl expose deployment nginx \
  --type=NodePort \
  --port=80
```

---

## Step 6: Access app

```bash id="mk6"
minikube service nginx --url
```

---

# 7. Debug Kubernetes

## Check resources

```bash id="dbg1"
kubectl get all
```

---

## Describe resource

```bash id="dbg2"
kubectl describe pod <pod-name>
```

---

## View logs

```bash id="dbg3"
kubectl logs <pod-name>
```

---

## Delete resource

```bash id="dbg4"
kubectl delete pod <pod-name>
```

---

# 8. Key Takeaways

* Pod là đơn vị nhỏ nhất
* Deployment quản lý Pod lifecycle
* Service giúp stable networking
* Scaling giúp handle traffic
* Minikube = Kubernetes local lab environment

---

# 9. Reflection

## Tôi đã hiểu:

* Kubernetes networking cơ bản
* Scaling manual và auto
* Service types
* Debug workflow

## Vấn đề gặp phải:

* ...

## Câu hỏi cho mentor:

1. Khi nào dùng HPA vs VPA?
2. NodePort có dùng production không?
3. CNI plugin ảnh hưởng networking thế nào?
4. Khi nào cần Ingress thay vì Service?

---

# 10. Evidence (bắt buộc)

* minikube start screenshot
* kubectl get pods
* kubectl get svc
* scaling demo
* service access browser screenshot

---

# Commit

```bash id="commit"
git add .
git commit -m "[W8-D3] Kubernetes scaling & networking"
git push origin main
```
