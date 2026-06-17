# W10 Day C — Platform Integration + Runbook + Cost Guard

## Mục tiêu

Hiểu cách ghép các phần đã học từ W8 đến W10 thành một mini platform có thể vận hành, kiểm soát tài nguyên, có runbook xử lý sự cố và có cảnh báo chi phí.

- Hiểu cách tích hợp các lớp đã học: Kubernetes foundation, GitOps, observability, canary, RBAC, secrets và supply chain security.
- Biết dùng `ResourceQuota` để giới hạn tổng tài nguyên trong namespace.
- Biết dùng `LimitRange` để đặt default request/limit cho workload.
- Hiểu chaos test là gì và cách chạy kiểm thử sự cố ở mức an toàn.
- Biết viết runbook ngắn, rõ, dùng được khi có incident.
- Biết vai trò của **AWS Cost Anomaly Detection** trong phát hiện chi phí bất thường.

Phạm vi self-study D3 theo W10:

| Chủ đề | Cần nắm được |
|---|---|
| Platform integration | Tích hợp stack W8 -> W10 thành một mini platform |
| ResourceQuota | Giới hạn tổng CPU, memory, object count trong namespace |
| LimitRange | Đặt default/min/max resource cho container |
| Chaos test | Cố ý tạo lỗi nhỏ để kiểm tra khả năng phục hồi |
| Runbook template | Tài liệu thao tác khi có sự cố |
| AWS Cost Anomaly Detection | Phát hiện chi phí AWS tăng bất thường |

---

## 1. Platform Integration là gì?

Platform integration là bước ghép các mảnh đã học thành một hệ thống chạy được end-to-end.

Trong W8 đến W10, các phần chính gồm:

| Tuần | Nội dung | Vai trò trong platform |
|---|---|---|
| W8 | Kubernetes foundation | Chạy workload trên cluster |
| W9 | GitOps, observability, canary | Deploy có kiểm soát, đo health, rollback khi lỗi |
| W10 Day A | RBAC + admission policy | Kiểm soát quyền và chặn manifest nguy hiểm |
| W10 Day B | Secrets + supply chain | Quản lý secret, scan/sign/verify image |
| W10 Day C | Runbook + cost guard | Vận hành, test sự cố, kiểm soát tài nguyên và chi phí |

Mục tiêu cuối W10 không phải là có nhiều file YAML rời rạc. Mục tiêu là có một mini platform mà người khác có thể deploy lại và kiểm tra được.

Luồng tích hợp nên hình dung:

```text
Git repository
  -> CI scan image bằng Trivy
  -> CI sign image bằng Cosign
  -> GitOps sync manifest vào cluster
  -> Admission policy kiểm tra manifest/image
  -> Workload chạy với quota/limit rõ ràng
  -> Observability đo health
  -> Runbook hướng dẫn xử lý khi lỗi
  -> Cost guard phát hiện chi phí bất thường
```

---

## 2. ResourceQuota là gì?

`ResourceQuota` dùng để giới hạn tổng tài nguyên mà một namespace được phép dùng.

Ví dụ namespace `dev` không được dùng quá:

- 2 CPU request.
- 4 GiB memory request.
- 4 CPU limit.
- 8 GiB memory limit.
- 10 Pod.

Ví dụ manifest:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "10"
```

Ý nghĩa:

- Nếu tổng request/limit trong namespace vượt quota, Kubernetes sẽ từ chối tạo workload mới.
- Quota giúp tránh một team hoặc một app dùng hết tài nguyên cluster.
- Quota đặc biệt hữu ích khi nhiều nhóm dùng chung cluster học tập hoặc cluster lab.

Kiểm tra quota:

```bash
kubectl describe resourcequota dev-quota -n dev
```

---

## 3. LimitRange là gì?

`LimitRange` đặt rule mặc định cho resource request/limit của container trong namespace.

Nếu developer quên khai báo `resources`, Kubernetes có thể tự gán default theo `LimitRange`.

Ví dụ:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: dev-limits
  namespace: dev
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: "100m"
        memory: 128Mi
      default:
        cpu: "500m"
        memory: 512Mi
      min:
        cpu: "50m"
        memory: 64Mi
      max:
        cpu: "1"
        memory: 1Gi
```

Ý nghĩa:

| Field | Vai trò |
|---|---|
| `defaultRequest` | Request mặc định nếu container không khai báo |
| `default` | Limit mặc định nếu container không khai báo |
| `min` | Resource nhỏ nhất được phép |
| `max` | Resource lớn nhất được phép |

`ResourceQuota` và `LimitRange` thường đi cùng nhau:

- `ResourceQuota` kiểm soát tổng tài nguyên namespace.
- `LimitRange` kiểm soát từng container/pod.

---

## 4. Chaos test là gì?

Chaos test là cố ý tạo một lỗi có kiểm soát để kiểm tra hệ thống có chịu được sự cố không.

Ví dụ chaos test đơn giản:

- Delete một pod và xem Deployment có tự tạo pod mới không.
- Scale service xuống 0 rồi kiểm tra alert có bắn không.
- Tạo image lỗi để kiểm tra canary auto-abort.
- Chặn network tạm thời để xem app degrade ra sao.

Nguyên tắc khi làm chaos test:

- Chỉ test trong môi trường lab hoặc namespace được phép.
- Có mục tiêu rõ: muốn kiểm tra điều gì?
- Có tiêu chí pass/fail.
- Có rollback plan.
- Ghi lại kết quả để đưa vào evidence.

Ví dụ test pod restart:

```bash
kubectl delete pod -l app=demo-api -n dev
kubectl get pods -n dev -w
```

Kỳ vọng:

- Pod cũ bị xóa.
- ReplicaSet tạo pod mới.
- Service vẫn route traffic khi pod mới ready.
- Alert hoặc dashboard thể hiện sự kiện restart nếu observability đã bật.

---

## 5. Runbook là gì?

Runbook là tài liệu hướng dẫn thao tác khi có sự cố hoặc khi cần vận hành hệ thống.

Một runbook tốt cần ngắn, rõ, làm được trong lúc đang căng thẳng. Không viết kiểu lý thuyết dài. Người trực vận hành cần đọc và làm theo được.

Template gợi ý:

````markdown
# Runbook: <Tên sự cố>

## Khi nào dùng

Mô tả dấu hiệu nhận biết sự cố.

## Mức độ ảnh hưởng

- User impact:
- Service impact:
- Severity:

## Kiểm tra nhanh

```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

## Cách xử lý

1. Bước kiểm tra đầu tiên.
2. Bước cô lập hoặc giảm ảnh hưởng.
3. Bước rollback hoặc restart nếu cần.
4. Bước xác nhận hệ thống đã phục hồi.

## Rollback

Lệnh hoặc quy trình rollback.

## Escalation

Ai cần được gọi nếu xử lý quá 15 phút hoặc ảnh hưởng tăng.

## Evidence cần lưu

- Screenshot dashboard.
- Log lỗi.
- Lệnh đã chạy.
- Thời gian bắt đầu/kết thúc.
````

Ví dụ runbook nên có cho W10:

- Pod crash loop.
- Canary fail hoặc rollout bị abort.
- Secret rotation làm app không kết nối được DB.
- Admission policy reject manifest.
- Namespace gần chạm quota.

---

## 6. Cost Guard là gì?

Cost guard là các cơ chế giúp phát hiện và giới hạn chi phí trước khi hóa đơn tăng ngoài dự kiến.

Trong AWS, các công cụ thường dùng:

| Công cụ | Vai trò |
|---|---|
| AWS Budgets | Cảnh báo khi chi phí vượt ngưỡng đặt trước |
| Cost Anomaly Detection | Phát hiện chi phí tăng bất thường bằng ML |
| Cost Explorer | Xem chi phí theo service, tag, thời gian |
| Tagging | Phân bổ chi phí theo project/team/environment |

Trong W10 D3, trọng tâm là **AWS Cost Anomaly Detection**.

---

## 7. AWS Cost Anomaly Detection

**AWS Cost Anomaly Detection** giúp phát hiện chi phí AWS tăng bất thường so với pattern sử dụng trước đó.

Ví dụ:

- NAT Gateway bị quên chạy.
- Load balancer tạo dư.
- Log ingestion tăng mạnh.
- Một service bắt đầu tạo chi phí bất thường.
- Cluster hoặc node group không được teardown đúng lúc.

Các khái niệm cần biết:

| Khái niệm | Ý nghĩa |
|---|---|
| Monitor | Phạm vi theo dõi chi phí, ví dụ toàn account hoặc service cụ thể |
| Alert subscription | Cách gửi cảnh báo, ví dụ email |
| Threshold | Mức impact tối thiểu để gửi alert |
| Root cause | Service/account/region gây anomaly |

Quy trình cấu hình cơ bản:

1. Vào AWS Console -> Cost Management -> Cost Anomaly Detection.
2. Tạo monitor cho account hoặc linked accounts.
3. Tạo alert subscription bằng email.
4. Chọn threshold phù hợp với môi trường lab.
5. Kiểm tra email đã nhận được subscription/alert.

Với repo học tập, nên ghi lại:

- Screenshot monitor đã bật.
- Email/subscription đã cấu hình.
- Tagging strategy nếu có.
- Ghi chú ngưỡng cảnh báo.

---

## 8. Bài tập nhỏ

Tạo thư mục trong repo cá nhân:

```text
cloud/
  w10/
    day-c/
      platform-bootstrap/
      quotas/
      chaos/
      runbooks/
      cost-guard/
```

Gợi ý nội dung:

| Thư mục | Nội dung |
|---|---|
| `platform-bootstrap/` | Ghi chú cách deploy lại stack W8-W10 |
| `quotas/` | `ResourceQuota` và `LimitRange` mẫu |
| `chaos/` | Kịch bản chaos test và kết quả |
| `runbooks/` | 1-2 runbook sự cố phổ biến |
| `cost-guard/` | Ghi chú AWS Cost Anomaly Detection |

Evidence tối thiểu:

```text
cloud/w10/day-c/evidence/
  resourcequota-describe.txt
  limitrange-describe.txt
  chaos-test-result.md
  runbook-pod-crashloop.md
  cost-anomaly-detection-notes.md
```

---

## 9. Lỗi thường gặp

### Lỗi 1: Có nhiều manifest nhưng không có luồng deploy rõ ràng

Platform integration cần chỉ ra cách deploy lại từ đầu. Nếu người khác không biết chạy bước nào trước, platform chưa thật sự hoàn chỉnh.

### Lỗi 2: Đặt quota quá thấp

Quota quá thấp có thể làm workload không deploy được. Cần tính request/limit hiện tại trước khi áp quota.

### Lỗi 3: Đặt limit nhưng không đặt request

Request giúp scheduler biết pod cần bao nhiêu tài nguyên. Nếu thiếu request, cluster dễ bị overcommit và khó dự đoán.

### Lỗi 4: Chaos test không có rollback

Không chạy chaos test nếu chưa biết cách khôi phục. Chaos test phải có phạm vi nhỏ và rollback rõ.

### Lỗi 5: Runbook quá dài hoặc quá chung chung

Runbook tốt phải thao tác được. Nếu chỉ viết "kiểm tra log và xử lý lỗi", tài liệu đó chưa đủ dùng khi có incident.

### Lỗi 6: Bật Cost Anomaly Detection nhưng không kiểm tra alert

Cấu hình mà không xác nhận email/subscription thì có thể không ai nhận cảnh báo khi chi phí tăng.

---

## 10. Tài liệu tham khảo

- Kubernetes ResourceQuota: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Kubernetes LimitRange: https://kubernetes.io/docs/concepts/policy/limit-range/
- AWS Cost Anomaly Detection: https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html
- LitmusChaos: https://litmuschaos.io/
- Chaos Mesh: https://chaos-mesh.org/
- Google SRE Workbook - Example Postmortem: https://sre.google/workbook/example-postmortem/

---

