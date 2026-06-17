# W10 Day A — RBAC + Admission Policy

## Mục tiêu

Hiểu cách kiểm soát quyền truy cập trong Kubernetes và cách dùng policy để chặn cấu hình không an toàn trước khi manifest được đưa vào cluster.

- Hiểu Kubernetes kiểm tra "ai được làm gì" bằng `Role`, `RoleBinding`, `ClusterRole`, `ClusterRoleBinding` và `ServiceAccount`.
- Thiết kế được quyền cơ bản cho các vai trò quen thuộc như `developer`, `sre`, `viewer` theo nguyên tắc least privilege.
- Dùng được `kubectl auth can-i` để kiểm tra một user hoặc ServiceAccount được phép hay bị từ chối.
- Hiểu vì sao RBAC chưa đủ để chặn các manifest nguy hiểm như pod privileged, image `latest`, thiếu resource limit.
- Phân biệt được `ConstraintTemplate` và `Constraint` trong Gatekeeper.
- Tạo được evidence học tập gồm manifest, kết quả test quyền và kết quả policy reject/allow để commit vào repo cá nhân.

Nói ngắn gọn, 2 lớp bảo vệ của Kubernetes:

- **RBAC** trả lời câu hỏi: "Bạn có quyền thực hiện hành động này không?"
- **Admission Policy** trả lời câu hỏi: "Manifest này có đủ an toàn để được nhận vào cluster không?"

Ví dụ:

- Developer có thể deploy app trong namespace `dev`.
- Developer không được xóa namespace, không được tạo `ClusterRole`, không được chạy pod privileged.
- SRE có quyền rộng hơn để vận hành cluster.
- Viewer chỉ được xem, không được sửa.

Phạm vi self-study D1 theo W10:

| Chủ đề | Cần nắm được |
|---|---|
| RBAC | `Role`, `RoleBinding`, `ClusterRole`, `ClusterRoleBinding` |
| ServiceAccount | Identity cho pod, job, controller hoặc CI/CD khi thao tác với Kubernetes API |
| Kiểm tra quyền | Dùng `kubectl auth can-i` để xác nhận quyền thực tế |
| OPA/Rego | Hiểu OPA là policy engine, Rego là ngôn ngữ viết rule |
| Gatekeeper | Phân biệt `ConstraintTemplate` và `Constraint` |
| ValidatingAdmissionPolicy | Biết cơ chế native của Kubernetes 1.30+ dùng CEL để validate object |
| Audit vs enforce | Biết khi nào chỉ ghi nhận vi phạm, khi nào chặn hẳn object vi phạm |


---

## 1. RBAC là gì và vì sao cần?

RBAC là viết tắt của **Role-Based Access Control**, nghĩa là kiểm soát quyền truy cập dựa trên vai trò.

Trong Kubernetes, RBAC được dùng để quy định một subject như user, group hoặc ServiceAccount được phép thực hiện hành động nào trên resource nào.

Kubernetes cluster thường có nhiều người và nhiều ứng dụng cùng dùng:

- Developer deploy ứng dụng.
- SRE vận hành cluster.
- CI/CD pipeline tự động apply manifest.
- Monitoring tool đọc metric/log.
- Application pod cần gọi Kubernetes API hoặc AWS API.

Nếu tất cả đều dùng quyền admin, một lỗi nhỏ có thể gây sự cố lớn:

- Xóa nhầm namespace.
- Đọc được secret của team khác.
- Tạo pod chạy quyền root.
- Tắt monitoring.
- Deploy image chưa được kiểm tra.

RBAC giúp giới hạn quyền theo nguyên tắc **least privilege**:

> Chỉ cấp đúng quyền cần thiết, trong đúng phạm vi cần thiết, cho đúng đối tượng cần thiết.

---

## 2. Các khái niệm RBAC quan trọng

### 2.1 Subject: ai đang xin quyền?

Trong RBAC, **subject** là đối tượng được cấp quyền.

Có 3 loại subject thường gặp:

| Loại | Ý nghĩa | Ví dụ |
|---|---|---|
| `User` | Người dùng thật hoặc identity từ bên ngoài | `alice`, `bob`, IAM user |
| `Group` | Nhóm người dùng | `developers`, `sre-team` |
| `ServiceAccount` | Identity cho pod/app trong cluster | `default`, `ci-deployer` |

#### ServiceAccount cần hiểu như thế nào?

`ServiceAccount` là danh tính dành cho workload chạy trong Kubernetes, ví dụ Pod, Job, CronJob, controller hoặc pipeline deploy vào cluster. Nếu `User` thường đại diện cho con người, thì `ServiceAccount` thường đại diện cho chương trình.

Ví dụ:

- Một app cần đọc ConfigMap trong namespace của nó.
- Một controller cần list Pod để theo dõi trạng thái.
- Một CI/CD pipeline cần tạo Deployment khi merge code.
- Một monitoring agent cần đọc thông tin Pod, Node hoặc Service.

Các workload này không nên dùng quyền admin hoặc dùng credential của người thật. Thay vào đó, ta tạo `ServiceAccount`, rồi dùng `RoleBinding` hoặc `ClusterRoleBinding` để cấp đúng quyền cần thiết.

Luồng tư duy khi dùng ServiceAccount:

```text
Pod/Job/CI cần làm gì?
  -> Tạo ServiceAccount riêng
  -> Tạo Role hoặc ClusterRole chứa đúng quyền cần thiết
  -> Gắn quyền bằng RoleBinding hoặc ClusterRoleBinding
  -> Test lại bằng kubectl auth can-i --as system:serviceaccount:<namespace>:<name>
```

Ví dụ tên đầy đủ của một ServiceAccount khi test quyền:

```text
system:serviceaccount:dev:app-deployer
```

Trong đó:

- `system:serviceaccount` là prefix Kubernetes dùng cho ServiceAccount.
- `dev` là namespace chứa ServiceAccount.
- `app-deployer` là tên ServiceAccount.

Khi Pod không chỉ định `serviceAccountName`, Kubernetes sẽ dùng ServiceAccount mặc định tên là `default` trong namespace đó. Đây là lý do nên kiểm tra quyền của `default` ServiceAccount và tránh cấp quyền rộng cho nó.

Điểm dễ nhầm:

- Kubernetes không tự quản lý user/password như app thông thường.
- User thường đến từ hệ thống bên ngoài như certificate, OIDC, IAM.
- `ServiceAccount` là object thật trong Kubernetes, thường dùng cho workload hoặc CI/CD.

Ví dụ tạo ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-deployer
  namespace: dev
```

### 2.2 Resource: quyền áp dụng lên cái gì?

Resource là các object trong Kubernetes:

- `pods`
- `deployments`
- `services`
- `configmaps`
- `secrets`
- `namespaces`
- `roles`
- `rolebindings`

Một số resource nằm trong namespace, ví dụ:

- Pod
- Deployment
- Service
- ConfigMap
- Secret

Một số resource ở cấp cluster, không thuộc namespace nào:

- Node
- Namespace
- ClusterRole
- ClusterRoleBinding

Đây là lý do Kubernetes có cả `Role` và `ClusterRole`.

### 2.3 Verb: được làm hành động gì?

Verb là hành động được phép thực hiện:

| Verb | Ý nghĩa |
|---|---|
| `get` | Xem một object cụ thể |
| `list` | Liệt kê nhiều object |
| `watch` | Theo dõi thay đổi |
| `create` | Tạo mới |
| `update` | Cập nhật toàn bộ |
| `patch` | Cập nhật một phần |
| `delete` | Xóa |

Ví dụ:

```yaml
verbs: ["get", "list", "watch"]
```

Nghĩa là chỉ được xem, không được sửa hoặc xóa.

---

## 3. Role, RoleBinding, ClusterRole, ClusterRoleBinding

Đây là 4 object quan trọng nhất của Kubernetes RBAC.

### 3.1 Role

`Role` định nghĩa một nhóm quyền trong **một namespace**.

Ví dụ: cho phép đọc pod trong namespace `dev`.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

Trong đó:

- `apiGroups: [""]` là core API group, dùng cho Pod, Service, ConfigMap, Secret.
- `resources: ["pods"]` là loại object được tác động.
- `verbs` là danh sách hành động được phép.

### 3.2 RoleBinding

`RoleBinding` gắn `Role` với một subject.

Ví dụ: gắn quyền `pod-reader` cho ServiceAccount `app-deployer`.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: dev
subjects:
  - kind: ServiceAccount
    name: app-deployer
    namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Hiểu đơn giản:

- `Role` trả lời: quyền gì?
- `RoleBinding` trả lời: quyền đó cấp cho ai?

### 3.3 ClusterRole

`ClusterRole` định nghĩa quyền ở cấp cluster, hoặc định nghĩa quyền có thể tái sử dụng ở nhiều namespace.

Ví dụ: quyền đọc node, vì node là resource cấp cluster.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
```

### 3.4 ClusterRoleBinding

`ClusterRoleBinding` gắn `ClusterRole` với subject ở cấp toàn cluster.

Ví dụ:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sre-node-reader
subjects:
  - kind: Group
    name: sre-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-reader
  apiGroup: rbac.authorization.k8s.io
```

Hãy cẩn thận với `ClusterRoleBinding`: nếu cấp sai, quyền có thể ảnh hưởng toàn cluster.

---

## 4. Khi nào dùng Role, khi nào dùng ClusterRole?

| Nhu cầu | Nên dùng |
|---|---|
| Chỉ cấp quyền trong một namespace | `Role` + `RoleBinding` |
| Cấp quyền với resource cấp cluster như `nodes`, `namespaces` | `ClusterRole` + `ClusterRoleBinding` |
| Muốn dùng cùng một bộ quyền cho nhiều namespace | `ClusterRole` + nhiều `RoleBinding` |
| Cấp quyền admin toàn cluster | `ClusterRoleBinding` rất hạn chế, chỉ cho SRE/admin |

Một pattern tốt:

- Developer: dùng `Role` trong namespace riêng.
- CI/CD: dùng `ServiceAccount` có quyền deploy trong namespace cần thiết.
- SRE: dùng `ClusterRole` được kiểm soát kỹ.
- Viewer: chỉ có `get/list/watch`.

---

## 5. Test quyền bằng kubectl auth can-i

Lệnh quan trọng nhất khi học RBAC:

```bash
kubectl auth can-i <verb> <resource> -n <namespace>
```

Ví dụ kiểm tra user hiện tại có được list pod trong namespace `dev` không:

```bash
kubectl auth can-i list pods -n dev
```

Kiểm tra một ServiceAccount cụ thể:

```bash
kubectl auth can-i create deployments \
  --as system:serviceaccount:dev:app-deployer \
  -n dev
```

Một số câu hỏi nên tự test:

```bash
kubectl auth can-i get pods -n dev
kubectl auth can-i create deployments -n dev
kubectl auth can-i delete namespaces
kubectl auth can-i get secrets -n dev
kubectl auth can-i create clusterroles
```

Nếu output là:

- `yes`: được phép.
- `no`: bị chặn bởi RBAC.

---

## 6. Bài tập RBAC nhỏ

Tạo thư mục trong repo cá nhân:

```text
cloud/
  w10/
    day-a/
      rbac/
        namespace.yaml
        serviceaccount.yaml
        developer-role.yaml
        developer-rolebinding.yaml
        viewer-role.yaml
        viewer-rolebinding.yaml
```

### 6.1 Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```

### 6.2 Developer ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: developer
  namespace: dev
```

### 6.3 Developer Role

Developer được quản lý app cơ bản, nhưng không được đọc secret.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-role
  namespace: dev
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

### 6.4 Developer RoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: dev
subjects:
  - kind: ServiceAccount
    name: developer
    namespace: dev
roleRef:
  kind: Role
  name: developer-role
  apiGroup: rbac.authorization.k8s.io
```

### 6.5 Test quyền

```bash
kubectl apply -f rbac/

kubectl auth can-i create deployments \
  --as system:serviceaccount:dev:developer \
  -n dev

kubectl auth can-i get secrets \
  --as system:serviceaccount:dev:developer \
  -n dev

kubectl auth can-i delete namespaces \
  --as system:serviceaccount:dev:developer
```

Kỳ vọng:

- Tạo deployment trong `dev`: `yes`
- Đọc secret trong `dev`: `no`
- Xóa namespace: `no`

---

## 7. RBAC chưa đủ: vì sao cần Admission Policy?

RBAC chỉ kiểm tra **ai được làm gì**.

RBAC không kiểm tra sâu nội dung manifest.

Ví dụ developer có quyền tạo Deployment. Nhưng Deployment đó có thể chứa cấu hình nguy hiểm:

```yaml
securityContext:
  privileged: true
```

Hoặc:

```yaml
containers:
  - name: app
    image: nginx:latest
```

Các vấn đề RBAC không xử lý tốt:

- Chặn container chạy `privileged`.
- Bắt buộc container chạy non-root.
- Chặn image tag `latest`.
- Bắt buộc có `resources.requests` và `resources.limits`.
- Chỉ cho phép image từ registry nội bộ.
- Bắt buộc có label như `owner`, `team`, `environment`.

Đó là việc của Admission Policy.

---

## 8. Admission Controller là gì?

Khi bạn chạy:

```bash
kubectl apply -f deployment.yaml
```

Manifest không đi thẳng vào etcd. Nó đi qua Kubernetes API Server.

Luồng đơn giản:

```text
kubectl
  -> API Server
  -> Authentication: bạn là ai?
  -> Authorization/RBAC: bạn có quyền không?
  -> Admission: object này có hợp lệ/an toàn không?
  -> etcd: lưu object
```

Admission có 2 kiểu chính:

- **Mutating admission**: có thể sửa object trước khi lưu.
- **Validating admission**: chỉ kiểm tra và cho qua hoặc từ chối.

Trong W10 Day A, ta tập trung vào validating policy: chặn cấu hình không đạt chuẩn.

---

## 9. OPA, Rego, Gatekeeper là gì?

### 9.1 OPA

OPA là viết tắt của **Open Policy Agent**.

OPA là engine dùng để đánh giá policy. Nó trả lời câu hỏi:

> Object này có vi phạm rule nào không?

OPA không chỉ dùng cho Kubernetes, nhưng Kubernetes là use case rất phổ biến.

Trong Kubernetes, OPA thường không được gọi trực tiếp bởi learner. Thay vào đó, một component như Gatekeeper sẽ nhận request từ Kubernetes API Server, gửi object sang OPA để đánh giá, rồi trả kết quả allow hoặc deny.

### 9.2 Rego

Rego là ngôn ngữ viết policy cho OPA.

Ví dụ ý tưởng bằng tiếng người:

> Từ chối nếu container dùng image tag `latest`.

Policy Rego sẽ mô tả logic đó dưới dạng code.

Bạn không cần giỏi Rego ngay ngày đầu. Cần hiểu:

- Input là object Kubernetes đang được submit.
- Policy kiểm tra các field trong input.
- Nếu có vi phạm, policy trả về message lỗi.

Một rule Rego thường có 3 phần:

| Thành phần | Ý nghĩa |
|---|---|
| `package` | Tên namespace logic của policy |
| `input` | Dữ liệu đầu vào, trong Kubernetes thường là admission review object |
| `violation` | Danh sách lỗi policy muốn trả về |

Ví dụ đọc logic này:

```rego
package k8sdisallowlatesttag

violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("container %v uses forbidden image tag latest", [container.name])
}
```

Cách hiểu từng dòng:

- `container := input.review.object.spec.containers[_]`: duyệt từng container trong Pod.
- `endswith(container.image, ":latest")`: kiểm tra image có kết thúc bằng `:latest` không.
- `msg := ...`: tạo thông báo lỗi để trả về cho người apply manifest.

Với người mới học, mục tiêu không phải là viết Rego phức tạp ngay. Mục tiêu là đọc được policy đang kiểm tra field nào và vì sao object bị reject.

### 9.3 Gatekeeper

Gatekeeper là cách phổ biến để đưa OPA vào Kubernetes.

Gatekeeper chạy như admission webhook. Khi có manifest mới được gửi vào API Server, Gatekeeper kiểm tra manifest theo policy bạn đã khai báo.

Gatekeeper có 2 loại object quan trọng:

| Object | Vai trò |
|---|---|
| `ConstraintTemplate` | Định nghĩa logic policy bằng Rego |
| `Constraint` | Bật policy đó với tham số cụ thể |

So sánh dễ hiểu:

- `ConstraintTemplate` giống như khuôn làm bánh.
- `Constraint` giống như một mẻ bánh cụ thể dùng khuôn đó.

Ví dụ:

- Template: "bắt buộc object phải có label".
- Constraint: "namespace `prod` bắt buộc có label `owner` và `team`".

Nói cách khác:

- `ConstraintTemplate` định nghĩa **loại policy mới** mà cluster hiểu được.
- `Constraint` tạo **một policy cụ thể** từ loại policy đó.

Ví dụ nếu `ConstraintTemplate` tạo ra kind `K8sRequiredLabels`, bạn có thể tạo nhiều `Constraint` khác nhau:

- Constraint A: namespace `dev` bắt buộc label `owner`.
- Constraint B: namespace `prod` bắt buộc label `owner`, `team`, `environment`.
- Constraint C: chỉ áp dụng cho `Deployment`, không áp dụng cho `Pod`.

---

## 10. Ví dụ policy: chặn image tag latest

Mục tiêu:

> Không cho deploy container dùng image tag `latest`, vì tag này không cố định. Hôm nay `latest` có thể là version A, ngày mai có thể là version B.

### 10.1 ConstraintTemplate

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowlatesttag
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowLatestTag
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowlatesttag

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          endswith(container.image, ":latest")
          msg := sprintf("container %v uses forbidden image tag latest", [container.name])
        }
```

### 10.2 Constraint

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowLatestTag
metadata:
  name: disallow-latest-tag
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

Sau khi apply policy, pod này sẽ bị từ chối:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
spec:
  containers:
    - name: nginx
      image: nginx:latest
```

Pod này hợp lệ hơn:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: good-pod
spec:
  containers:
    - name: nginx
      image: nginx:1.27.0
```

Ghi chú: trong production vẫn nên dùng digest để cố định image mạnh hơn nữa, ví dụ `nginx@sha256:...`.

---

## 11. Audit mode và enforce mode

Khi đưa policy vào cluster, không nên bật chặn mạnh ngay lập tức nếu chưa biết có bao nhiêu workload đang vi phạm.

Hai chế độ triển khai policy:

| Chế độ | Ý nghĩa | Khi dùng |
|---|---|---|
| Audit | Ghi nhận vi phạm, chưa chặn | Khi mới khảo sát cluster |
| Enforce | Chặn object vi phạm | Khi policy đã rõ và team đã sẵn sàng |

Trong Gatekeeper, chế độ này thường được điều khiển bằng `enforcementAction`.

Ví dụ chạy ở chế độ audit/dryrun:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowLatestTag
metadata:
  name: disallow-latest-tag
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

Với `dryrun`, Gatekeeper ghi nhận vi phạm nhưng không chặn request. Cách này phù hợp khi bạn mới đưa policy vào một cluster đã có workload chạy sẵn.

Ví dụ bật enforce:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowLatestTag
metadata:
  name: disallow-latest-tag
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

Với `deny`, object vi phạm sẽ bị Kubernetes API Server từ chối.

Quy trình tốt:

1. Viết policy.
2. Chạy audit để xem workload nào vi phạm.
3. Sửa workload.
4. Bật enforce.
5. Thêm exception nếu thật sự cần, có lý do và thời hạn.

Không nên tạo exception kiểu "cho qua mãi mãi". Exception không có deadline thường biến thành nợ bảo mật.

Checklist trước khi chuyển từ audit sang enforce:

- Đã biết policy áp dụng cho namespace/kind nào.
- Đã kiểm tra workload hiện tại có bao nhiêu vi phạm.
- Đã sửa các workload quan trọng hoặc tạo exception có thời hạn.
- Đã thông báo cho team trước khi policy bắt đầu chặn deploy.
- Đã có cách rollback nếu policy chặn nhầm.

---

## 12. ValidatingAdmissionPolicy native trong Kubernetes

Ngoài Gatekeeper, Kubernetes có **ValidatingAdmissionPolicy** native. Đây là cơ chế admission policy có sẵn trong Kubernetes, dùng để validate object ngay trong API Server bằng ngôn ngữ **CEL**.

Trong scope W10, bạn cần nhớ mốc: **Kubernetes 1.30+** là baseline nên biết và đọc hiểu ValidatingAdmissionPolicy native. Với cluster cũ hơn, trạng thái hỗ trợ có thể khác tùy version và cấu hình API server.

Ý tưởng:

- Không cần cài OPA/Gatekeeper.
- Viết rule bằng CEL, một ngôn ngữ expression nhẹ.
- Phù hợp cho một số rule đơn giản.

Ví dụ use case:

- Bắt buộc label.
- Chặn field nguy hiểm.
- Kiểm tra naming convention.

So sánh nhanh:

| Tiêu chí | Gatekeeper/OPA | ValidatingAdmissionPolicy |
|---|---|---|
| Cài thêm component | Có | Không hoặc ít hơn |
| Ngôn ngữ policy | Rego | CEL |
| Policy phức tạp | Mạnh hơn | Phù hợp rule vừa/nhỏ |
| Hệ sinh thái policy mẫu | Rộng | Native Kubernetes |

Ví dụ ValidatingAdmissionPolicy chặn Pod dùng image `latest`:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: disallow-latest-tag
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, !c.image.endsWith(':latest'))"
      message: "container image must not use the latest tag"
```

Để policy có hiệu lực, cần tạo thêm `ValidatingAdmissionPolicyBinding`:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: disallow-latest-tag-binding
spec:
  policyName: disallow-latest-tag
  validationActions: ["Deny"]
```

Trong ví dụ trên:

- `ValidatingAdmissionPolicy` định nghĩa rule.
- `ValidatingAdmissionPolicyBinding` bật rule đó và quyết định hành động.
- `validationActions: ["Deny"]` nghĩa là chặn object vi phạm.

Nếu muốn quan sát trước khi chặn, có thể dùng `Warn` hoặc `Audit` tùy mục tiêu rollout policy:

```yaml
validationActions: ["Warn", "Audit"]
```

Khi nào nên dùng Gatekeeper, khi nào nên dùng ValidatingAdmissionPolicy:

| Tình huống | Gợi ý |
|---|---|
| Lab W10 yêu cầu OPA/Gatekeeper | Dùng Gatekeeper |
| Cần policy phức tạp, có nhiều policy mẫu sẵn | Dùng Gatekeeper/OPA |
| Cần rule đơn giản, muốn dùng native Kubernetes | Dùng ValidatingAdmissionPolicy |
| Team đã quen Rego | Gatekeeper dễ chuẩn hóa hơn |
| Team muốn giảm component cài thêm | ValidatingAdmissionPolicy phù hợp hơn |

Trong W10, nếu lab yêu cầu Gatekeeper thì ưu tiên Gatekeeper. Tuy vậy, bạn cần biết ValidatingAdmissionPolicy vì đây là hướng native trong Kubernetes 1.30+.

---

## 13. Lỗi thường gặp

### Lỗi 1: Nhầm namespace

Bạn tạo `Role` ở namespace `dev`, nhưng test ở namespace khác.

Cách kiểm tra:

```bash
kubectl get role -n dev
kubectl get rolebinding -n dev
```

### Lỗi 2: Quên `--as` khi test ServiceAccount

Nếu không dùng `--as`, bạn đang test quyền của user hiện tại, không phải ServiceAccount.

Đúng:

```bash
kubectl auth can-i create deployments \
  --as system:serviceaccount:dev:developer \
  -n dev
```

### Lỗi 3: Sai `apiGroups`

Một số resource thuộc core group dùng `apiGroups: [""]`.

Ví dụ:

- `pods`
- `services`
- `configmaps`
- `secrets`

Deployment thuộc group `apps`:

```yaml
apiGroups: ["apps"]
resources: ["deployments"]
```

### Lỗi 4: Tạo policy nhưng không match đúng kind

Nếu policy chỉ match `Pod`, nhưng bạn apply `Deployment`, cần nhớ Deployment tạo Pod thông qua controller. Tùy policy và webhook, bạn có thể cần kiểm tra cả Pod template hoặc dùng policy mẫu hỗ trợ workload controller.

Khi mới học, hãy test trực tiếp với Pod trước để hiểu cơ chế.

---

## 14. Tài liệu tham khảo

- Kubernetes RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Kubernetes Authorization: https://kubernetes.io/docs/reference/access-authn-authz/authorization/
- OPA Docs: https://www.openpolicyagent.org/docs/
- Gatekeeper Docs: https://open-policy-agent.github.io/gatekeeper/website/docs/
- Kubernetes ValidatingAdmissionPolicy: https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
- Kubernetes Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/

---
