# W9-D3 Progressive Delivery (Canary)

> **Ngày:** 10/06/2026  
> **Chủ đề:** Argo Rollouts, Rollout CRD, AnalysisTemplate, Progressive Delivery patterns, canary auto-abort  


---

## 📖 Mục Lục

1. [Progressive Delivery Fundamentals](#progressive-delivery-fundamentals)
2. [Argo Rollouts Architecture](#argo-rollouts-architecture)
3. [Rollout CRD Deep Dive](#rollout-crd-deep-dive)
4. [AnalysisTemplate & Abort Criteria](#analysistemplate--abort-criteria)
5. [Prometheus Queries for Canary](#prometheus-queries-for-canary)
6. [Canary Deployment Strategy](#canary-deployment-strategy)
7. [Integration với Burn Rate Alerts](#integration-với-burn-rate-alerts)
8. [Ví Dụ Thực Hành](#ví-dụ-thực-hành)
9. [Troubleshooting & Best Practices](#troubleshooting--best-practices)
10. [Những Điểm Chính](#những-điểm-chính)

---

## 1️⃣ Progressive Delivery Fundamentals

### Deployment Strategies So Sánh

```
┌──────────────┬──────────┬─────────────┬──────────────┐
│ Strategy     │ Risk     │ Rollback    │ Speed        │
├──────────────┼──────────┼─────────────┼──────────────┤
│ Blue-Green   │ Medium   │ Instant     │ Fast         │
│ Canary       │ Low      │ Gradual     │ Medium       │
│ Rolling      │ High     │ Slow        │ Slow         │
│ Feature Flag │ Very Low │ Instant     │ Very Fast    │
└──────────────┴──────────┴─────────────┴──────────────┘
```

### Canary Deployment Flow

```
1. Current (Stable)
   └─ 100% traffic → v1.0 (Pod set A)

2. Deployment Triggered
   └─ New version v1.1 created (Pod set B) with 0 traffic

3. Canary Phase (5 minutes)
   └─ 10% traffic → v1.1
   └─ 90% traffic → v1.0
   └─ Prometheus: Thatch metrics từ both versions

4. Analysis
   └─ Compare: p95_latency(v1.1) vs p95_latency(v1.0)
   └─ If p95_latency(v1.1) < 1000ms → Continue
   └─ Else → Abort, rollback to v1.0

5. Stable Phase
   └─ 100% traffic → v1.1
   └─ v1.0 pods deleted
   └─ Deployment complete ✅

Or on failure:
   └─ Metrics fail → Auto-rollback to v1.0
   └─ Manual review of failure logs
```

### Why Canary?

✅ **Low risk** — mỗi bước nhỏ thử nghiệm trước toàn bộ  
✅ **Metric-driven** — dựa vào SLO, không phải gut feeling  
✅ **Automatic rollback** — tự động lùi lại nếu xấu  
✅ **Quick feedback** — biết trong 5-10 phút nếu có vấn đề  
✅ **Compliance** — audit trail (mỗi bước ghi lại)

---

## 2️⃣ Argo Rollouts Architecture

### Argo Rollouts Overview

**Argo Rollouts** = Kubernetes native progressive delivery controller

```
Argo Rollouts (Controller)
    ↓
Watches: Rollout CRD
    ↓
┌─────────────────────┐
│ Rollout Spec:       │
│ - Image: v1.1       │
│ - Strategy: canary  │
│ - Analysis: enabled │
└─────────────────────┘
    ↓
Creates Replica Sets
    ↓
┌──────────────────────────┐
│ Stable RS:  v1.0 (80%)   │
│ Canary RS:  v1.1 (20%)   │
│ Service:    route traffic│
└──────────────────────────┘
    ↓
AnalysisRun (nếu enabled)
    ↓
Prometheus Query + Compare
    ↓
✅ Promote canary → 100%
❌ Or abort
```

### Install Argo Rollouts

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f \
  https://github.com/argoproj/argo-rollouts/releases/download/v1.6.0/install.yaml

# Verify
kubectl get deployment -n argo-rollouts
# rollouts-controller (running)
```

### Argo Rollouts CLI

```bash
# Install CLI
curl -LO https://github.com/argoproj/argo-rollouts/releases/download/v1.6.0/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Commands
kubectl argo rollouts list rollouts -n default
kubectl argo rollouts status <rollout-name> -n default
kubectl argo rollouts promote <rollout-name> -n default  # promote canary → stable
kubectl argo rollouts abort <rollout-name> -n default    # abort & rollback
kubectl argo rollouts set image <rollout-name> \
  <container>=<image> -n default
```

---

## 3️⃣ Rollout CRD Deep Dive

### Rollout Spec Structure

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: payment-service
  namespace: default
spec:
  # 1. Replicas
  replicas: 5
  
  # 2. Selector
  selector:
    matchLabels:
      app: payment
  
  # 3. Strategy: Canary
  strategy:
    canary:
      steps:
        - setWeight: 10      # Step 1: 10% canary
          pause:
            duration: 5m     # Chạy 5 phút rồi analysis
        
        - setWeight: 50      # Step 2: 50% canary
          pause:
            duration: 5m
        
        - setWeight: 100     # Step 3: 100% (promote)
      
      # Stable service (routing all traffic initially)
      stableService: payment-stable
      # Canary service (routing canary traffic)
      canaryService: payment-canary
      
      # Traffic Management (optional: Istio, SMI, etc.)
      trafficManagement:
        istio: {}  # or: smi: {}, linkerd: {}
  
  # 4. Analysis
  analysis:
    templates:
      - name: payment-analysis
        requiredForProgression: true  # Must pass to continue
        interval: 1m
        count: 1                        # Run once per window
  
  # 5. Pod Template (same as Deployment)
  template:
    metadata:
      labels:
        app: payment
    spec:
      containers:
      - name: payment
        image: myregistry.azurecr.io/payment:v1.1  # New version
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
```

### Canary Steps Variations

**Option 1: Duration-based (paused analysis)**
```yaml
steps:
  - setWeight: 20
    pause:
      duration: 5m      # Wait 5m, then auto-run analysis
```

**Option 2: Manual promotion (require kubectl)**
```yaml
steps:
  - setWeight: 20
    pause: {}           # Wait for manual kubectl argo rollouts promote
```

**Option 3: Multiple analysis checks**
```yaml
steps:
  - setWeight: 10
    pause:
      duration: 3m
  - setWeight: 25
    pause:
      duration: 3m
  - setWeight: 50
    pause:
      duration: 3m
  - setWeight: 100
```

---

## 4️⃣ AnalysisTemplate & Abort Criteria

### AnalysisTemplate Structure

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: payment-analysis
  namespace: default
spec:
  # Metrics to measure
  metrics:
    # Metric 1: Error Rate
    - name: error-rate
      interval: 1m
      count: 1
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            (sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) /
             sum(rate(http_requests_total{job="payment"}[1m]))) * 100
      # Abort if error rate > 5%
      failureLimit: 1
      threshold: 5
    
    # Metric 2: P95 Latency
    - name: p95-latency
      interval: 1m
      count: 1
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="payment"}[1m])) * 1000
      # Abort if p95 > 1000ms
      failureLimit: 1
      threshold: 1000
    
    # Metric 3: Request Success Rate
    - name: success-rate
      interval: 1m
      count: 1
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            (sum(rate(http_requests_total{job="payment",status="200"}[1m])) /
             sum(rate(http_requests_total{job="payment"}[1m]))) * 100
      # Warn if < 99%
      failureLimit: 1
      threshold: 99
```

### failureLimit vs successCriteria

```yaml
# failureLimit: number of failures to tolerate
- name: error-rate
  failureLimit: 2       # Abort after 2 failed checks
  threshold: 5          # Fail if metric > 5
  count: 3              # Run 3 times (at 1m interval)
  
  # Scenarios:
  # - 2 pass, 1 fail → 1 failure, continue
  # - 2 fail, 1 pass → 2 failures, ABORT
  # - 3 fail → ABORT immediately

# successCriteria: minimum passes required (default: all)
- name: latency
  successCriteria: 2    # Only need 2 out of 3 to pass
  count: 3              # Run 3 times
```

### Using Rollout Analysis in Spec

```yaml
# In Rollout spec.analysis
analysis:
  templates:
    - name: payment-analysis              # Reference AnalysisTemplate
  args:
    - name: "stable-pod-hash"
      value: "{{ .StableRevision }}"      # Stable version pod hash
    - name: "latest-pod-hash"
      value: "{{ .PodTemplateHash }}"     # Canary version pod hash
```

---

## 5️⃣ Prometheus Queries for Canary

### Query Patterns

**Error Rate (by version/pod)**
```promql
# All requests
sum(rate(http_requests_total{job="payment"}[1m])) by (pod)

# Only errors
sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) by (pod)

# Error rate percentage
(sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) by (pod) /
 sum(rate(http_requests_total{job="payment"}[1m])) by (pod)) * 100
```

**Latency by Version**
```promql
# Histogram buckets (from OTel)
histogram_quantile(0.95, 
  sum(rate(http_request_duration_seconds_bucket{job="payment"}[1m])) by (pod, le))
```

**Canary vs Stable Comparison**
```promql
# Canary error rate
canary_error_rate = (sum(rate(http_requests_total{job="payment",pod=~"payment-canary.*",status=~"5.."}[1m])) /
                    sum(rate(http_requests_total{job="payment",pod=~"payment-canary.*"}[1m]))) * 100

# Stable error rate
stable_error_rate = (sum(rate(http_requests_total{job="payment",pod=~"payment-stable.*",status=~"5.."}[1m])) /
                    sum(rate(http_requests_total{job="payment",pod=~"payment-stable.*"}[1m]))) * 100

# Delta (canary - stable)
delta = canary_error_rate - stable_error_rate
```

**For AnalysisTemplate (single query)**
```yaml
# If no pod labels, aggregate whole job
- name: error-rate
  query: |
    (sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) /
     sum(rate(http_requests_total{job="payment"}[1m]))) * 100
  
  # Abort if > 5%
  threshold: 5
```

---

## 6️⃣ Canary Deployment Strategy

### Step-by-Step Canary Flow

**Setup:**
```yaml
# 1. Create AnalysisTemplate
kubectl apply -f analysis-template.yaml

# 2. Create Rollout (replaces Deployment)
kubectl apply -f rollout.yaml

# 3. Create Services
kubectl apply -f services.yaml
```

**Rollout Process (Auto):**
```
0min: Create rollout, canary pods start (0 traffic)
     └─ wait 5m for analysis

5min: Analysis runs
     └─ If pass → setWeight to 50
     └─ If fail → Auto-abort, delete canary pods

10min: Canary at 50% traffic
      └─ wait 5m for next analysis

15min: Analysis runs
      └─ If pass → setWeight to 100
      └─ If fail → Auto-abort

20min: All traffic on canary (v1.1)
      └─ Stable pods (v1.0) deleted
      └─ Rollout complete ✅
```

### Traffic Management with Istio (Optional)

```yaml
# If using Istio VirtualService for traffic split
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: payment
spec:
  hosts:
  - payment
  http:
  - match:
    - uri:
        prefix: /api/v1
    route:
    - destination:
        host: payment
        subset: stable
      weight: 90          # ← Updated by Argo Rollouts
    - destination:
        host: payment
        subset: canary
      weight: 10          # ← Updated by Argo Rollouts

---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: payment
spec:
  host: payment
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
```

---

## 7️⃣ Integration với Burn Rate Alerts

### SLO-driven Canary Abort

**Scenario:**
```
Burn Rate Alert Triggered (from D2)
  → Payment error rate = 10% (10× error budget)
  → Fire alert "HighErrorRateFast"
  → Concurrent: New canary deployment → auto-abort due to high error rate

Result: Safer canary (don't deploy when already on fire)
```

### AnalysisTemplate with SLO Context

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: payment-slo-aware-analysis
spec:
  metrics:
    # Metric 1: Absolute error rate (canary)
    - name: error-rate-canary
      interval: 1m
      count: 3
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            (sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) /
             sum(rate(http_requests_total{job="payment"}[1m]))) * 100
      # SLO: error_rate < 0.5%, abort if > 1%
      failureLimit: 2
      threshold: 1
    
    # Metric 2: Delta (canary - stable)
    - name: error-rate-delta
      interval: 1m
      count: 1
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            ((sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) /
              sum(rate(http_requests_total{job="payment"}[1m]))) * 100) -
            ((sum(rate(http_requests_total{job="payment-stable",status=~"5.."}[1m])) /
              sum(rate(http_requests_total{job="payment-stable"}[1m]))) * 100)
      # If canary error rate is 2% worse than stable, abort
      failureLimit: 1
      threshold: 2
    
    # Metric 3: Burn rate (fast window)
    - name: burn-rate-fast
      interval: 1m
      count: 1
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            # Burn rate = (error_rate / error_budget)
            # SLO: 99.5% → 0.5% error budget
            # Fast burn: > 6% error rate → burn 12× per hour
            (sum(rate(http_requests_total{job="payment",status=~"5.."}[5m])) /
             sum(rate(http_requests_total{job="payment"}[5m])))
      failureLimit: 1
      threshold: 0.06       # 6% error = 12× burn
```

### Integration: Rollout + Burn Rate Alert

**Prometheus Alert Rule:**
```yaml
- alert: HighErrorRateFast
  expr: (sum(rate(http_requests_total{job="payment", status=~"5.."}[5m])) / sum(rate(http_requests_total{job="payment"}[5m]))) > 0.06
  annotations:
    action: "kubectl argo rollouts abort payment -n default"
```

**Webhook Action (Manual/Automated):**
```bash
# When alert fires, webhook triggers:
curl -X POST http://controller/api/v1/rollouts/payment/abort \
  -H "Content-Type: application/json" \
  -d '{"reason":"High error rate detected"}'
```

---

## 8️⃣ Ví Dụ Thực Hành

### Lab 1: Basic Canary with Error Rate Abort

**Step 1: Create AnalysisTemplate**

```yaml
# analysis-template.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: payment-canary-analysis
spec:
  metrics:
  - name: error-rate
    interval: 30s
    count: 2
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          (sum(rate(http_requests_total{job="payment",status=~"5.."}[30s])) /
           sum(rate(http_requests_total{job="payment"}[30s]))) * 100
    failureLimit: 1
    threshold: 5
```

**Step 2: Create Rollout**

```yaml
# rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: payment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payment
  strategy:
    canary:
      steps:
      - setWeight: 25
        pause:
          duration: 30s
      - setWeight: 75
        pause:
          duration: 30s
      - setWeight: 100
      stableService: payment-stable
      canaryService: payment-canary
    analysis:
      templates:
      - name: payment-canary-analysis
        requiredForProgression: true
        interval: 30s
        count: 1
  template:
    metadata:
      labels:
        app: payment
    spec:
      containers:
      - name: payment
        image: myregistry.azurecr.io/payment:v1.1
        ports:
        - containerPort: 8080
```

**Step 3: Create Services**

```yaml
# services.yaml
apiVersion: v1
kind: Service
metadata:
  name: payment
spec:
  selector:
    app: payment
  ports:
  - port: 80
    targetPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: payment-stable
spec:
  selector:
    app: payment
    rollouts-stable-pod-hash: ""
  ports:
  - port: 80
    targetPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: payment-canary
spec:
  selector:
    app: payment
    rollouts-pod-template-hash: ""
  ports:
  - port: 80
    targetPort: 8080
```

**Step 4: Apply & Monitor**

```bash
# Apply
kubectl apply -f analysis-template.yaml
kubectl apply -f services.yaml
kubectl apply -f rollout.yaml

# Monitor status
kubectl argo rollouts status payment -n default --watch

# View analysis
kubectl get analysisruns -n default

# Manual abort if needed
kubectl argo rollouts abort payment -n default
```

### Lab 2: SLO-Aware Canary with Burn Rate

**Create enhanced AnalysisTemplate:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: payment-slo-canary
spec:
  metrics:
  - name: error-rate
    interval: 1m
    count: 3
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          (sum(rate(http_requests_total{job="payment",status=~"5.."}[1m])) /
           sum(rate(http_requests_total{job="payment"}[1m]))) * 100
    failureLimit: 2
    threshold: 1
  
  - name: p95-latency
    interval: 1m
    count: 3
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="payment"}[1m])) * 1000
    failureLimit: 2
    threshold: 500
```

**Update Rollout with longer canary window:**

```yaml
strategy:
  canary:
    steps:
    - setWeight: 20
      pause:
        duration: 5m
    - setWeight: 50
      pause:
        duration: 5m
    - setWeight: 100
    analysis:
      templates:
      - name: payment-slo-canary
        requiredForProgression: true
        interval: 1m
        count: 1
```

---

## 9️⃣ Troubleshooting & Best Practices

### Common Issues

**Issue 1: Analysis never runs**

```
Symptoms: Rollout stuck at setWeight step
Cause: AnalysisTemplate not found or invalid query

Fix:
kubectl get analysistemplate
kubectl describe analysisrun <name>
# Check Prometheus query syntax
```

**Issue 2: Canary pods not receiving traffic**

```
Symptoms: Canary pods created but no requests hit them
Cause: Service selector not matching, or traffic management misconfigured

Fix:
# Verify service selectors
kubectl get svc payment-canary -o yaml | grep selector

# Verify pod labels
kubectl get pods -L rollouts-stable-pod-hash,rollouts-pod-template-hash

# If using Istio, check VirtualService
kubectl get virtualservice
kubectl describe vs payment
```

**Issue 3: Abort criteria too strict**

```
Symptoms: Every canary aborts immediately
Cause: threshold set too low relative to baseline

Fix:
# Check current baseline metrics
# In Prometheus: query error-rate, latency
# Adjust threshold to (baseline + 2σ)

# Example:
# If stable error rate = 0.5%, set canary threshold to 1%
# If stable p95 = 400ms, set threshold to 500ms
```

### Best Practices

✅ **Start with loose criteria**, tighten over time
```yaml
# Week 1: error_rate threshold: 10%
# Week 2: error_rate threshold: 5%
# Week 3: error_rate threshold: 2%
```

✅ **Use multiple metrics** (not just error rate)
```yaml
metrics:
  - error-rate
  - p95-latency
  - success-rate     # catch silent failures
```

✅ **Canary window ≥ 5 minutes** để capture transient issues
```yaml
pause:
  duration: 5m       # minimum
```

✅ **Set failureLimit conservatively**
```yaml
failureLimit: 2      # tolerate 1 blip, abort on 2nd
count: 3             # measure 3 times
```

✅ **Use stableService & canaryService** cho traffic routing clarity
```yaml
stableService: payment-stable      # 90% traffic
canaryService: payment-canary      # 10% traffic
```

✅ **Monitor AnalysisRun logs** để debug metrics
```bash
kubectl logs -f <analysisrun-name> -n default
```

---

## 🔟 Những Điểm Chính


1. **Canary = low-risk progressive delivery**
   - Mỗi bước nhỏ: 10% → 50% → 100%
   - Analysis chạy giữa các bước
   - Abort tự động nếu metric xấu

2. **Argo Rollouts** = Kubernetes-native canary operator
   - Rollout CRD (thay thế Deployment)
   - AnalysisTemplate (thay thế ad-hoc monitoring)
   - Auto-abort & rollback

3. **AnalysisTemplate** = reusable metric checks
   - Prometheus queries
   - failureLimit & threshold
   - Integration với Rollout steps

4. **SLO + Canary = safer deployments**
   - Burn rate alerts → don't deploy if system unhealthy
   - Canary analysis → verify new version is good
   - Error budget respected

5. **Traffic management** (Istio, SMI, etc.)
   - Automatic traffic split (10% → canary)
   - Gradual ramp-up
   - No manual VirtualService edits


### 📚 Tài Nguyên Tham Khảo

- Argo Rollouts Docs: https://argoproj.github.io/argo-rollouts
- Rollout Examples: https://github.com/argoproj/argo-rollouts/tree/master/examples
- Progressive Delivery (CNCF): https://www.cncf.io/blog/2024/01/26/progressive-delivery/
- Google SRE: https://sre.google


