# W10 Day B — Secrets Rotation + Supply Chain Security

## Mục tiêu

Hiểu cách quản lý secret an toàn hơn trong Kubernetes và cách bảo vệ chuỗi build/deploy để tránh đưa image không an toàn vào cluster.

- Hiểu vì sao không nên lưu secret trực tiếp trong Git hoặc hard-code trong manifest.
- Biết vai trò của **AWS Secrets Manager** trong lưu trữ và rotation secret.
- Hiểu cách **External Secrets Operator (ESO)** đồng bộ secret từ AWS Secrets Manager về Kubernetes Secret.
- Biết dùng **Trivy** để scan container image trong CI.
- Phân biệt được **Cosign keyless OIDC** và **Cosign key-based signing**.
- Hiểu admission webhook verify signature là lớp chặn image chưa được ký hoặc ký sai.
- Biết cách viết exception policy cho CVE có lý do, owner và thời hạn.

Phạm vi self-study D2 theo W10:

| Chủ đề | Cần nắm được |
|---|---|
| AWS Secrets Manager | Lưu secret tập trung, versioning, rotation |
| External Secrets Operator | Sync secret từ AWS về Kubernetes |
| Trivy image scan | Scan vulnerability trong CI trước khi deploy |
| Cosign signing | Ký image bằng keyless OIDC hoặc key-based |
| Admission verify signature | Chặn image chưa ký ở cluster level |
| Exception policy CVE | Cho phép tạm thời CVE có kiểm soát, không bỏ qua vô thời hạn |

---

## 1. Vì sao cần quản lý Secrets đúng cách?

Secret là thông tin nhạy cảm mà ứng dụng cần để hoạt động:

- Database username/password.
- API key.
- OAuth client secret.
- Token gọi service nội bộ.
- Private key hoặc certificate.

Các lỗi phổ biến:

- Commit secret vào Git.
- Hard-code password trong source code.
- Lưu secret trong file `.env` rồi đẩy nhầm lên repo.
- Tạo Kubernetes Secret thủ công nhưng không có rotation.
- Dùng chung một secret cho nhiều môi trường.

Kubernetes Secret mặc định chỉ là object lưu trong cluster. Nó không tự giải quyết toàn bộ bài toán quản lý vòng đời secret như rotation, audit, versioning hay phân quyền truy cập từ cloud provider.

Vì vậy trong W10, mô hình nên hiểu là:

```text
AWS Secrets Manager
  -> External Secrets Operator
  -> Kubernetes Secret
  -> Pod dùng secret qua env hoặc volume
```

---

## 2. AWS Secrets Manager là gì?

**AWS Secrets Manager** là dịch vụ của AWS để lưu trữ, quản lý và rotate secret.

Các điểm cần nắm:

| Khả năng | Ý nghĩa |
|---|---|
| Store secret | Lưu password, API key, token dưới dạng secret |
| Versioning | Mỗi lần cập nhật secret có version mới |
| Rotation | Có thể tự động đổi secret theo lịch |
| IAM access control | Quy định role nào được đọc secret nào |
| Audit | CloudTrail ghi lại ai truy cập secret |

Ví dụ secret trong AWS Secrets Manager có thể có dạng JSON:

```json
{
  "username": "app_user",
  "password": "change-me"
}
```

Trong thực tế, app không nên gọi AWS Secrets Manager trực tiếp nếu đang chạy trên Kubernetes mà chưa thiết kế kỹ. Một pattern phổ biến là dùng ESO để sync secret cần thiết về Kubernetes Secret trong namespace phù hợp.

---

## 3. External Secrets Operator là gì?

**External Secrets Operator (ESO)** là controller chạy trong Kubernetes. ESO đọc secret từ external provider như AWS Secrets Manager, AWS Parameter Store, Vault, GCP Secret Manager, Azure Key Vault, rồi tạo hoặc cập nhật Kubernetes Secret.

Luồng hoạt động:

```text
ExternalSecret manifest
  -> ESO controller đọc AWS Secrets Manager
  -> ESO tạo/cập nhật Kubernetes Secret
  -> Pod consume Kubernetes Secret
```

Các object quan trọng:

| Object | Vai trò |
|---|---|
| `SecretStore` | Cấu hình nơi lấy secret, ví dụ AWS Secrets Manager |
| `ClusterSecretStore` | Giống `SecretStore` nhưng dùng được toàn cluster |
| `ExternalSecret` | Khai báo secret nào cần sync về namespace hiện tại |
| `Secret` | Kubernetes Secret được ESO tạo ra |

Ví dụ `ExternalSecret`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-db-secret
  namespace: dev
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: app-db-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: dev/app/db
        property: username
    - secretKey: password
      remoteRef:
        key: dev/app/db
        property: password
```

Trong ví dụ trên:

- `refreshInterval: 1m`: ESO kiểm tra secret mới mỗi 1 phút.
- `target.name`: tên Kubernetes Secret sẽ được tạo.
- `remoteRef.key`: tên secret trong AWS Secrets Manager.
- `property`: field cụ thể trong secret JSON.

---

## 4. Secrets Rotation cần hiểu thế nào?

**Rotation** là quá trình thay secret cũ bằng secret mới theo cách có kiểm soát.

Ví dụ: đổi database password mỗi 30 ngày hoặc ngay sau khi nghi ngờ secret bị lộ.

Một rotation tốt cần trả lời được:

- Secret mới được tạo ở đâu?
- Ai hoặc hệ thống nào có quyền cập nhật secret?
- Ứng dụng nhận secret mới bằng cách nào?
- Có cần restart pod không?
- Nếu secret mới lỗi, rollback ra sao?

Với ESO, khi secret trong AWS Secrets Manager thay đổi, ESO sẽ sync giá trị mới về Kubernetes Secret theo `refreshInterval`.

Lưu ý quan trọng:

- Kubernetes Secret đổi không có nghĩa app tự đọc lại giá trị mới nếu app chỉ load env var lúc start.
- Nếu app đọc secret từ mounted volume, kubelet có thể cập nhật file sau một khoảng thời gian.
- Nếu app dùng env var, thường cần restart pod để nhận giá trị mới.
- Mục tiêu lab W10 có thể yêu cầu rotate secret trong thời gian ngắn, ví dụ dưới 60 giây, nên cần hiểu app consume secret bằng cách nào.

---

## 5. Supply Chain Security là gì?

Supply chain security là bảo vệ toàn bộ đường đi từ source code đến image chạy trong cluster.

Luồng cơ bản:

```text
Source code
  -> CI build
  -> Image scan
  -> Image signing
  -> Push registry
  -> Admission verify
  -> Deploy vào cluster
```

Nếu thiếu kiểm soát, các rủi ro có thể xảy ra:

- Image chứa CVE nghiêm trọng vẫn được deploy.
- Image bị thay đổi sau khi build.
- Developer deploy image chưa đi qua CI.
- Cluster chạy image từ registry không tin cậy.
- Không biết image đang chạy được build từ commit nào.

D2 tập trung vào 3 lớp bảo vệ chính:

- **Scan** image bằng Trivy.
- **Sign** image bằng Cosign.
- **Verify** signature bằng admission policy/webhook trước khi cho chạy trong cluster.

---

## 6. Trivy image scan trong CI

**Trivy** là công cụ scan vulnerability phổ biến cho container image, filesystem, dependency và IaC config.

Trong CI, Trivy thường được dùng sau bước build image và trước bước push/deploy.

Ví dụ command:

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 my-app:sha-abc123
```

Ý nghĩa:

- Chỉ quan tâm vulnerability mức `HIGH` và `CRITICAL`.
- Nếu tìm thấy lỗi phù hợp điều kiện, Trivy trả exit code `1`.
- CI fail, image không được deploy.

Ví dụ GitHub Actions tối giản:

```yaml
name: image-security

on:
  pull_request:
  push:
    branches: ["main"]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t my-app:${{ github.sha }} .

      - name: Scan image with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: my-app:${{ github.sha }}
          severity: HIGH,CRITICAL
          exit-code: "1"
```

Policy gợi ý:

| Severity | Hành động |
|---|---|
| `CRITICAL` | Fail CI, không deploy |
| `HIGH` | Fail CI, trừ khi có exception được duyệt |
| `MEDIUM` | Ghi nhận, lên kế hoạch xử lý |
| `LOW` | Theo dõi |

---

## 7. Cosign signing là gì?

**Cosign** là công cụ ký và xác minh container image. Mục tiêu là chứng minh image được build bởi pipeline tin cậy và chưa bị thay đổi.

Có 2 cách ký cần biết trong W10:

| Cách ký | Ý nghĩa | Khi dùng |
|---|---|---|
| Keyless OIDC | Dùng identity từ CI provider như GitHub Actions, không cần quản lý private key lâu dài | Khuyến nghị cho CI hiện đại |
| Key-based | Dùng cặp public/private key | Phù hợp khi cần kiểm soát key thủ công |

### 7.1 Keyless OIDC

Keyless signing dùng OIDC identity của CI để ký image. Với GitHub Actions, signature có thể gắn với repo, workflow và commit.

Ví dụ:

```bash
cosign sign my-registry.example.com/my-app:${GITHUB_SHA}
```

Ưu điểm:

- Không phải lưu private key dài hạn trong secret của CI.
- Có thể verify image được ký bởi đúng GitHub repo hoặc workflow.
- Giảm rủi ro lộ signing key.

### 7.2 Key-based signing

Key-based signing dùng private key để ký và public key để verify.

Ví dụ tạo key:

```bash
cosign generate-key-pair
```

Ký image:

```bash
cosign sign --key cosign.key my-registry.example.com/my-app:1.0.0
```

Verify image:

```bash
cosign verify --key cosign.pub my-registry.example.com/my-app:1.0.0
```

Điểm cần cẩn thận:

- Private key phải được bảo vệ như secret quan trọng.
- Cần có quy trình rotate key.
- Cần biết ai có quyền ký image production.

---

## 8. Admission webhook verify signature

Scan và sign trong CI là cần thiết, nhưng chưa đủ. Nếu cluster vẫn cho deploy image chưa ký, một người có quyền deploy có thể bypass CI.

Vì vậy cần thêm lớp verify ở admission:

```text
kubectl apply Deployment
  -> Kubernetes API Server
  -> Admission webhook kiểm tra image signature
  -> Nếu signature hợp lệ: cho qua
  -> Nếu thiếu hoặc sai signature: reject
```

Các tool thường dùng cho verify image:

- Kyverno `verifyImages`.
- Sigstore Policy Controller.
- Gatekeeper policy tùy biến.

Ví dụ ý tưởng policy:

```text
Chỉ cho phép image từ registry tin cậy.
Image phải được ký bởi identity tin cậy.
Không cho chạy image tag latest.
Không cho deploy image không có digest/signature.
```

Ví dụ Kyverno policy dạng rút gọn:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-image-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "my-registry.example.com/*"
          attestations: []
```

Ví dụ trên chỉ để hiểu vị trí của verify policy. Khi làm thật cần cấu hình đúng registry, public key hoặc OIDC issuer/subject theo tool đang dùng.

---

## 9. Exception policy cho CVE

Không phải CVE nào cũng có thể sửa ngay. Có trường hợp image base chưa có bản vá, hoặc vulnerability nằm trong package không được app sử dụng.

Tuy nhiên exception không được hiểu là "bỏ qua cho xong". Exception phải có kiểm soát.

Một exception CVE tốt cần có:

| Trường | Ý nghĩa |
|---|---|
| CVE ID | Ví dụ `CVE-2026-12345` |
| Severity | `HIGH`, `CRITICAL`, ... |
| Image/package bị ảnh hưởng | Image nào, package nào |
| Lý do chấp nhận tạm thời | Vì sao chưa fix ngay |
| Risk assessment | Rủi ro thực tế với app |
| Mitigation | Biện pháp giảm rủi ro tạm thời |
| Owner | Ai chịu trách nhiệm xử lý |
| Expiry date | Ngày exception hết hạn |
| Approval | Ai duyệt exception |

Ví dụ template ngắn:

```markdown
## CVE Exception

- CVE: CVE-2026-12345
- Severity: HIGH
- Image: my-registry.example.com/my-app:1.2.3
- Package: openssl
- Reason: Base image chưa có bản vá tại thời điểm build.
- Risk: App không expose tính năng bị ảnh hưởng ra public path.
- Mitigation: NetworkPolicy giới hạn inbound, WAF rule đã bật.
- Owner: platform-team
- Expiry: 2026-07-15
- Approval: mentor/security-review
```

Quy tắc quan trọng:

- Exception phải có thời hạn.
- Exception phải có owner.
- Exception phải được review lại.
- Không tạo exception chung chung cho mọi image hoặc mọi CVE.

---

## 10. Bài tập nhỏ

Tạo thư mục trong repo cá nhân:

```text
cloud/
  w10/
    day-b/
      eso/
      ci-trivy/
      signing/
      exceptions/
```

Gợi ý nội dung:

| Thư mục | Nội dung |
|---|---|
| `eso/` | Manifest `ExternalSecret` mẫu và ghi chú rotation |
| `ci-trivy/` | Workflow scan image bằng Trivy |
| `signing/` | Command ký/verify image bằng Cosign |
| `exceptions/` | Template exception CVE |

Evidence tối thiểu:

```text
cloud/w10/day-b/evidence/
  trivy-scan-result.txt
  cosign-sign-verify.txt
  eso-sync-notes.md
  cve-exception-example.md
```

---

## 11. Lỗi thường gặp

### Lỗi 1: Commit secret vào Git

Không commit `.env`, private key, kubeconfig, token hoặc password. Nếu lỡ commit secret, không chỉ xóa file khỏi Git là xong. Cần rotate secret vì secret đã bị lộ trong lịch sử commit.

### Lỗi 2: Nghĩ Kubernetes Secret là đủ an toàn

Kubernetes Secret không thay thế cho secret manager. Cần phân quyền, encryption at rest, audit và rotation.

### Lỗi 3: App không nhận secret mới sau rotation

Nếu app đọc secret qua env var, app thường cần restart để nhận giá trị mới. Nếu cần no-restart rotation, app nên đọc secret từ mounted file hoặc có cơ chế reload config.

### Lỗi 4: Scan image nhưng vẫn cho deploy image chưa scan

Nếu chỉ scan trong CI nhưng cluster không verify signature hoặc provenance, người dùng vẫn có thể deploy image bypass CI. Admission verify giúp chặn đường vòng này.

### Lỗi 5: Exception CVE không có ngày hết hạn

Exception không có expiry date sẽ trở thành nợ bảo mật. Mỗi exception cần owner và ngày review lại.

---

## 12. Tài liệu tham khảo

- AWS Secrets Manager: https://docs.aws.amazon.com/secretsmanager/
- External Secrets Operator: https://external-secrets.io/latest/
- Trivy: https://aquasecurity.github.io/trivy/
- Cosign: https://docs.sigstore.dev/cosign/overview/
- Sigstore Policy Controller: https://docs.sigstore.dev/policy-controller/overview/
- Kyverno verify images: https://kyverno.io/docs/writing-policies/verify-images/
- SLSA: https://slsa.dev/

---

