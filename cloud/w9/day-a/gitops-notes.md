# W9-D1 GitOps & CI/CD

> **Ngày:** 08/06/2026  
> **Chủ đề:** Nguyên tắc GitOps, ArgoCD, GitHub Actions, App-of-Apps  


---

## 📖 Mục Lục

1. [Nguyên Tắc GitOps](#nguyên-tắc-gitops)
2. [Nền Tảng ArgoCD](#nền-tảng-argocd)
3. [Mẫu App of Apps](#mẫu-app-of-apps)
4. [GitHub Actions CI/CD](#github-actions-cicd)
5. [Chiến Lược Triển Khai](#chiến-lược-triển-khai)
6. [So Sánh ArgoCD và Flux](#so-sánh-argocd-và-flux)
7. [Ví Dụ Thực Hành](#ví-dụ-thực-hành)
8. [Những Điểm Chính](#những-điểm-chính)

---

## 1️⃣ Nguyên Tắc GitOps

### GitOps là gì?

**GitOps** là mô hình hoạt động cho các ứng dụng cloud-native có:
- Sử dụng **Git làm nguồn chân lý duy nhất** (SSoT) cho các config khai báo về cơ sở hạ tầng & ứng dụng
- Tự động hóa việc triển khai & hoạt động qua **luồng công việc Git** (PR, merge, commit)
- Triển khai **điều hòa liên tục**: trạng thái mong muốn (trong Git) so với trạng thái thực tế (trong cluster)

### 4 Nguyên Tắc Cốt Lõi GitOps (OpenGitOps)

| Nguyên Tắc | Mô Tả | Tại Sao Quan Trọng |
|-----------|-------------|-----------|
| **1. Khai Báo** | Hệ thống được mô tả bằng các config khai báo trong Git (không phải lệnh bắt buộc) | Quản lý phiên bản, khả năng kiểm tra, khả năng tái tạo |
| **2. Phiên Bản Hóa & Bất Biến** | Tất cả config trong Git với lịch sử phiên bản, tags, branches | Dấu vết kiểm tra đầy đủ, khả năng khôi phục |
| **3. Kéo Tự Động** | Hệ thống tự động điều hòa trạng thái thực tế ↔ trạng thái mong muốn | Không có kubectl apply thủ công, tự chữa lành |
| **4. Điều Hòa Liên Tục** | Các toán tử phát hiện drift & tự động sửa | Khả năng chịu đựng, triển khai nhất quán |

### GitOps vs CI/CD Truyền Thống

| Khía Cạnh | CI/CD Truyền Thống | GitOps |
|--------|------------------|--------|
| **Kích Hoạt** | Webhook → xây dựng → **đẩy** tới cluster | Git commit → điều hòa (kéo) từ cluster |
| **Nguồn Chân Lý** | Tạo phẩm pipeline + registry | **Git repository** |
| **Khôi Phục** | Chạy lại pipeline với tag cũ | `git revert` + ArgoCD auto-sync |
| **Phát Hiện Drift** | Helm diff thủ công / kubectl diff | **Tự động, liên tục** |
| **Bảo Mật** | Tài khoản Pod/service có quyền rộng với cluster | Chỉ Git token, cluster **read-only tới repo** |

**Lợi ích chính:** Cluster không thể đẩy tới repo (chỉ kéo) → an toàn hơn, thân thiện với kiểm tra.

---

## 2️⃣ Nền Tảng ArgoCD

### ArgoCD là gì?

**ArgoCD** = triển khai liên tục khai báo GitOps cho Kubernetes.

```
Git Repo (config khai báo) 
        ↓ (ArgoCD giám sát)
   ArgoCD Controller
        ↓ (điều hòa)
   Kubernetes Cluster
        ↓ (kubectl apply)
   Các Pod đang chạy
```

### Các Khái Niệm Cốt Lõi ArgoCD

#### **A. Ứng Dụng (CRD)**

Đơn vị nhỏ nhất: ánh xạ 1 nguồn Git repo → 1 đích K8s cluster.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  # Nguồn: nơi kéo config từ đó
  source:
    repoURL: https://github.com/myorg/my-app-config.git
    path: manifests/      # thư mục trong repo
    targetRevision: main  # branch/tag
  
  # Đích đến: nơi triển khai tới
  destination:
    server: https://kubernetes.default.svc  # cluster cục bộ
    namespace: default
  
  # Chính sách auto-sync
  syncPolicy:
    automated:
      prune: true        # xóa tài nguyên bị xóa khỏi Git
      selfHeal: true     # sửa drift tự động
    syncOptions:
      - CreateNamespace=true
```

**Các trường chính:**
- `source`: Git repo + thư mục + branch
- `destination`: cluster + namespace
- `syncPolicy`: config auto-sync

#### **B. AppProject**

Ranh giới RBAC: hạn chế repos & clusters mà một ứng dụng có thể truy cập.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
spec:
  sourceRepos:
    - 'https://github.com/myorg/*'  # repos được phép (hỗ trợ wildcards)
  destinations:
    - namespace: 'default'           # namespace được phép
      server: 'https://kubernetes.default.svc'
  clusterResourceWhitelist:          # cho phép tài nguyên toàn cluster
    - group: '*'
      kind: '*'
```

#### **C. Trạng Thái Sync**

ArgoCD liên tục báo cáo trạng thái đồng bộ:

| Trạng Thái | Ý Nghĩa | Sửa Tự Động |
|--------|---------|----------|
| **Synced** | Thực tế == Mong muốn (Git) | N/A |
| **OutOfSync** | Thực tế ≠ Mong muốn (phát hiện drift) | Auto-sync nếu bật |
| **Unknown** | Không thể so sánh (vấn đề kết nối) | N/A |

**Ví dụ thực tế:**
- Ai đó chạy `kubectl delete pod my-pod`
- ArgoCD phát hiện drift
- Nếu auto-sync bật → ArgoCD tự động tạo lại pod

### Quy Trình Làm Việc ArgoCD

```
1. Nhà phát triển commit config → Git repo (nhánh main)
2. Bộ điều khiển ArgoCD giám sát repo
3. Phát hiện thay đổi → kéo config mới
4. So sánh mong muốn (Git) vs thực tế (cluster)
5. Nếu khác → kubectl apply config mới
6. Giám sát cho đến khi Synced
7. Nếu phát hiện drift sau → prune/tạo lại tài nguyên
```

**Quá trình đồng bộ:**
- Git commit → 3-5 giây (khoảng kiểm tra mặc định)
- Có thể thiết lập webhook để phát hiện ngay lập tức

---

## 3️⃣ Mẫu App of Apps

### Tại Sao App of Apps?

Một CRD `Application` duy nhất cho mỗi microservice hoạt động, nhưng:
- 10 dịch vụ = 10 CRD để quản lý
- Cập nhật tất cả 10 cùng lúc = khó khăn
- Không có cách nào để nhóm các ứng dụng liên quan

**Giải pháp:** App of Apps = meta-app quản lý các ứng dụng khác.

### Cách Hoạt Động

```
git-repo/
├── apps/                          # repo "App of Apps"
│   ├── values.yaml               # config trung tâm
│   ├── Chart.yaml (Helm)
│   └── templates/
│       ├── payment-app.yaml      # tạo CRD Application
│       ├── auth-app.yaml
│       ├── notification-app.yaml
│       └── fraud-app.yaml

├── manifests/                    # manifests ứng dụng riêng
│   ├── payment/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── auth/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── ... (các dịch vụ khác)
```

**CRD "App of Apps" Application:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: w8-platform
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/myorg/platform-config.git
    path: apps/                    # Helm chart hoặc Kustomize
    targetRevision: main
  
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

---
# Khi được đồng bộ, tự động tạo các Ứng dụng này:
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: w8-payment
spec:
  source:
    repoURL: https://github.com/myorg/platform-config.git
    path: manifests/payment/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: default

---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: w8-auth
spec:
  source:
    repoURL: https://github.com/myorg/platform-config.git
    path: manifests/auth/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: default
```

### App of Apps Dựa Trên Helm

**Cấu trúc biểu đồ:**

```
platform-config/
├── Chart.yaml
├── values.yaml              # {apps: [payment, auth, notification, fraud]}
└── templates/
    └── app-template.yaml
```

**templates/app-template.yaml:**

```yaml
{{- range .Values.apps }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: w8-{{ . }}
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/myorg/platform-config.git
    path: manifests/{{ . }}/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
{{- end }}
```

**values.yaml:**

```yaml
apps:
  - payment
  - auth
  - notification
  - fraud
```

**Kết quả:** Một biểu đồ Helm tạo 4 Ứng dụng tự động.

### Lợi Ích

✅ **Nguồn chân lý duy nhất** cho tất cả các ứng dụng  
✅ **Tính nhất quán** giữa các triển khai  
✅ **Mở rộng dễ dàng** — thêm tên ứng dụng vào values.yaml  
✅ **Chính sách sync tập trung** — tất cả ứng dụng kế thừa cùng quy tắc  
✅ **Sync waves** — kiểm soát thứ tự triển khai (payment trước fraud, vv)

### Sync Waves

Kiểm soát **thứ tự triển khai** trong App of Apps:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Triển khai thứ 1
spec:
  ...

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fraud-detector
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Triển khai thứ 2 (sau payment sẵn sàng)
spec:
  ...

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification
  annotations:
    argocd.argoproj.io/sync-wave: "3"  # Triển khai thứ 3
spec:
  ...
```

**Thực thi:**
1. Sync wave 0 (mặc định) — tất cả tài nguyên không được đánh dấu
2. Sync wave 1 — payment
3. Sync wave 2 — fraud-detector
4. Sync wave 3 — notification

---

## 4️⃣ GitHub Actions CI/CD

### Quy Trình: plan-on-PR + apply-on-merge

Mẫu GitOps tiêu chuẩn:

```
Feature branch → PR → GitHub Actions test
                        ↓
                      [plan] (Helm/Kustomize diff)
                        ↓
                    PR review + approve
                        ↓
                      Merge to main
                        ↓
                GitHub Actions apply
                        ↓
              kubectl apply / Helm deploy
```

### Ví Dụ: plan-on-PR Workflow

```yaml
# .github/workflows/plan.yml
name: Plan on PR

on:
  pull_request:
    paths:
      - 'manifests/**'  # chỉ nếu manifests/ thay đổi

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: Show manifests changes
        run: |
          git diff origin/main...HEAD manifests/
      
      - name: Validate YAML
        run: |
          for file in manifests/**/*.yaml; do
            kubectl apply -f "$file" --dry-run=client
          done
      
      - name: Helm dry-run
        run: |
          helm template w8-platform ./platform-config \
            --values values.yaml \
            --dry-run > /tmp/helm-output.yaml
      
      - name: Show what will be deployed
        run: |
          echo "=== Proposed changes ==="
          diff <(git show origin/main:manifests/) <(cat /tmp/helm-output.yaml) || true
      
      - name: Comment on PR with plan
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '✅ Plan complete\n```\n' + fs.readFileSync('/tmp/helm-output.yaml', 'utf8') + '\n```'
            })
```

### Ví Dụ: apply-on-merge Workflow

```yaml
# .github/workflows/apply.yml
name: Apply on Merge

on:
  push:
    branches:
      - main
    paths:
      - 'manifests/**'

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure kubectl
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > $HOME/.kube/config
          chmod 600 $HOME/.kube/config
      
      - name: Helm deploy
        run: |
          helm repo add myrepo https://myrepo.example.com
          helm repo update
          helm upgrade --install w8-platform ./platform-config \
            --values values.yaml \
            --namespace default \
            --create-namespace
      
      - name: Verify deployment
        run: |
          kubectl rollout status deployment/payment -n default
          kubectl rollout status deployment/auth -n default
          kubectl get all -n default
      
      - name: Slack notification
        if: always()
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -d '{"text":"✅ Deployment to main successful"}'
```

### Quản Lý Bí Mật

**Lưu trữ trong GitHub:**
- `KUBE_CONFIG` — kubeconfig được mã hóa base64
- `DOCKER_USERNAME` / `DOCKER_PASSWORD` — thông tin xác thực registry
- `SLACK_WEBHOOK` — thông báo

**Truy cập trong workflow:**
```yaml
echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > kubeconfig.yaml
```

---

## 5️⃣ Chiến Lược Triển Khai

### 1. Direct Apply (Đơn Giản)

```
Git commit → GitHub Actions → kubectl apply
```

✅ Nhanh  
❌ Không có khôi phục tự động  
❌ Các lệnh kubectl thủ công vẫn có thể thực hiện được

### 2. GitOps với ArgoCD (Được Khuyến Nghị)

```
Git commit → GitHub Actions (chỉ kiểm tra/xác nhận)
            → ArgoCD phát hiện thay đổi
            → ArgoCD kéo config & áp dụng
            → ArgoCD giám sát cho đến khi Synced
```

✅ Tự chữa lành (tự động điều hòa drift)  
✅ Khôi phục tự động (git revert)  
✅ Dấu vết kiểm tra (tất cả thông qua Git)  
✅ Không cần truy cập trực tiếp cluster  

### 3. GitOps với Flux (Thay Thế)

Tương tự ArgoCD nhưng:
- Nhẹ hơn
- Kiến trúc GitOps Toolkit
- Hỗ trợ đa cluster tốt hơn

### Chiến Lược Khôi Phục

**Truyền thống:** kubectl rollout undo
```bash
kubectl rollout undo deployment/payment
```
❌ Mất lịch sử phiên bản  
❌ Trạng thái cluster không trong Git

**GitOps (Được Khuyến Nghị):** git revert
```bash
git revert HEAD~1   # hoàn tác commit cuối cùng
git push origin main
# ArgoCD tự động đồng bộ & triển khai lại phiên bản trước đó
```
✅ Dấu vết kiểm tra đầy đủ  
✅ Cluster đồng bộ tự động  
✅ Có thể chọn lựa các dịch vụ để khôi phục

---

## 6️⃣ So Sánh ArgoCD và Flux

| Khía Cạnh | ArgoCD | Flux |
|--------|--------|------|
| **Kiến Trúc** | Tập trung UI (máy chủ ArgoCD) | Phân tán (bộ điều khiển GitOps Toolkit) |
| **UI** | UI phong phú kèm theo | Tập trung CLI, UI tùy chọn |
| **Đường Cong Học** | Dễ hơn (UI giúp) | Cao hơn (YAML-heavy) |
| **Sử Dụng Tài Nguyên** | Cao hơn (UI + API server) | Thấp hơn (bộ điều khiển tối thiểu) |
| **Đa Cluster** | Thông qua ApplicationSet (mới hơn) | Hỗ trợ đa cluster native |
| **RBAC** | Tích hợp sẵn thông qua AppProject | Thông qua Kustomize RBAC |
| **Cộng Đồng** | Lớn hơn, nhiều tích hợp hơn | Đang phát triển, Cloud Native |
| **Trường Hợp Sử Dụng** | Single-cluster + ưa thích UI | Multi-cluster + GitOps-first |

**Đối với nền tảng W8:** Khuyên dùng ArgoCD (đơn giản hơn, UI giúp gỡ lỗi)

---

## 7️⃣ Ví Dụ Thực Hành

### Ví Dụ 1: Triển Khai Dịch Vụ Thanh Toán W8 với ArgoCD

**Bước 1: Tạo cấu trúc Git repo**

```
w8-platform-config/
├── apps/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/app-template.yaml
├── manifests/
│   ├── payment/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── auth/
│   └── fraud/
└── README.md
```

**Bước 2: Tạo payment deployment.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
  namespace: default
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payment
  template:
    metadata:
      labels:
        app: payment
    spec:
      containers:
      - name: payment-app
        image: myregistry.azurecr.io/payment:v1.0
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: payment-secrets
              key: db-url
```

**Bước 3: Tạo ArgoCD Application**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: w8-payment
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/myorg/w8-platform-config.git
    path: manifests/payment/
    targetRevision: main
  
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Bước 4: Áp dụng & giám sát**

```bash
# Áp dụng CRD Application
kubectl apply -f payment-app.yaml

# Giám sát đồng bộ
argocd app get w8-payment
# hoặc thông qua UI: localhost:8080
```

### Ví Dụ 2: GitHub Actions plan-on-PR

Xem **Phần 4** để biết ví dụ quy trình hoàn chỉnh.

---

## 8️⃣ Những Điểm Chính


1. **GitOps = Git là SSoT** cho cả config ứng dụng & cơ sở hạ tầng
   - Tất cả khai báo
   - Điều hòa tự động
   - Tự chữa lành theo mặc định

2. **ArgoCD = triển khai dựa trên kéo**
   - Cluster chỉ giám sát Git
   - An toàn (không cần thông tin xác thực cluster trong pipeline)
   - Phát hiện drift & tự động sửa

3. **App of Apps** mở rộng GitOps tới nhiều microservice
   - Một Helm chart tạo ra nhiều Applications
   - Sync waves kiểm soát thứ tự triển khai
   - values.yaml trung tâm để đảm bảo tính nhất quán

4. **CI/CD + GitOps = tốt nhất của cả hai**
   - GitHub Actions: kiểm tra & xác nhận PRs
   - ArgoCD: triển khai & điều hòa
   - Git commits thúc đẩy mọi thứ

5. **Khôi phục trong GitOps = git revert**
   - Dấu vết kiểm tra đầy đủ
   - Đồng bộ cluster tự động
   - Không cần kubectl undo

### 🎯 Bước Tiếp Theo (D2-D3)

- Thiết lập Prometheus + Grafana cho các chỉ số SLO
- Tìm hiểu Argo Rollouts cho triển khai canary
- Thực hành hủy canary trên ngưỡng chỉ số

### 📚 Tài Nguyên Được Sử Dụng

- ArgoCD Docs: https://argo-cd.readthedocs.io
- GitHub Actions: https://docs.github.com/en/actions
- Flux Docs: https://fluxcd.io
- OpenGitOps: https://opengitops.dev



