# W9-D2 Observability — SLO/SLI/OTel

> **Ngày:** 09/06/2026  
> **Chủ đề:** OpenTelemetry fundamentals, OTel SDK + Collector, SLO/SLI/SLA, Prometheus + Grafana + Loki, multi-window burn rate alerts  


---

## 📖 Mục Lục

1. [OpenTelemetry Fundamentals](#opentelemetry-fundamentals)
2. [OTel SDK & Instrumentation](#otel-sdk--instrumentation)
3. [OTel Collector](#otel-collector)
4. [SLO/SLI/SLA Concepts](#slosliisla-concepts)
5. [Prometheus Fundamentals](#prometheus-fundamentals)
6. [Grafana Dashboards](#grafana-dashboards)
7. [Loki for Logs](#loki-for-logs)
8. [Multi-Window Burn Rate Alerts](#multi-window-burn-rate-alerts)
9. [Ví Dụ Thực Hành](#ví-dụ-thực-hành)
10. [Những Điểm Chính](#những-điểm-chính)

---

## 1️⃣ OpenTelemetry Fundamentals

### OpenTelemetry là gì?

**OpenTelemetry (OTel)** là tiêu chuẩn mở cho việc thu thập dữ liệu observability từ các ứng dụng:
- **Traces** — theo dõi các yêu cầu xuyên suốt hệ thống
- **Metrics** — đo lường hiệu suất (latency, throughput, errors)
- **Logs** — ghi lại sự kiện & lỗi

### 3 Trụ Cột Observability (Three Pillars)

```
┌─────────┬──────────┬─────────┐
│ Traces  │ Metrics  │  Logs   │
├─────────┼──────────┼─────────┤
│ "What   │ "How    │ "What   │
│ happened│ is it   │ was said│
│ when?"  │ doing?" │ about   │
│         │         │ it?"    │
└─────────┴──────────┴─────────┘
```

**Traces** — Distributed tracing
```
User Request
    ↓
[Payment API]  (span 1: 50ms)
    ├─ Query DB (span 1.1: 30ms)
    ├─ Call Fraud Service (span 1.2: 15ms)
    └─ Update Cache (span 1.3: 5ms)
    ↓
[Response]
```

**Metrics** — Time-series data
```
- payment.latency_ms{p95: 50}
- payment.errors{code: 500, count: 2/min}
- payment.throughput{req/sec: 100}
```

**Logs** — Structured events
```
{
  "timestamp": "2026-06-09T10:30:00Z",
  "level": "ERROR",
  "service": "payment",
  "message": "Failed to charge card",
  "user_id": "usr_123",
  "trace_id": "abc123xyz"
}
```

### OTel Architecture

```
Application Code
    ↓
OTel SDK (auto-instrumented)
    ↓
OTel API (vendor-neutral)
    ↓
Exporters (Jaeger, Prometheus, OTLP)
    ↓
Backends (Jaeger for traces, Prometheus for metrics, Loki for logs)
    ↓
Visualization (Grafana, Datadog, etc.)
```

### Tại Sao OTel?

✅ **Vendor-neutral** — không khóa vào Datadog hay New Relic  
✅ **Unified** — cùng một SDK cho traces, metrics, logs  
✅ **Auto-instrumentation** — không cần viết code tracing thủ công  
✅ **Production-ready** — được các công ty lớn (Google, AWS, Alibaba) hỗ trợ

---

## 2️⃣ OTel SDK & Instrumentation

### OTel SDK Setup (Node.js Example)

```javascript
// index.js
const opentelemetry = require('@opentelemetry/api');
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');

// 1. Khởi tạo SDK
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-collector:4318/v1/traces',
  }),
  metricExporter: new OTLPMetricExporter({
    url: 'http://otel-collector:4318/v1/metrics',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

// 2. Khởi động SDK
sdk.start();
console.log('OTel SDK started');

// 3. Ứng dụng của bạn
const express = require('express');
const app = express();

app.get('/payment', (req, res) => {
  // Traces & metrics tự động thu thập
  res.json({ status: 'ok' });
});

app.listen(3000);
```

### Instrumentation Libraries

**Auto-instrumentation** (khuyên dùng cho development):
```bash
npm install @opentelemetry/auto-instrumentations-node
```
Tự động trace: HTTP, Database, Redis, etc. không cần code thêm.

**Manual instrumentation** (chi tiết hơn):

```javascript
const { trace } = require('@opentelemetry/api');
const tracer = trace.getTracer('my-service', '1.0.0');

function processPayment(userId, amount) {
  const span = tracer.startSpan('processPayment', {
    attributes: {
      'user.id': userId,
      'payment.amount': amount,
      'payment.currency': 'USD',
    },
  });

  try {
    // Span con: database query
    const dbSpan = tracer.startSpan('db.query', { parent: span });
    const result = await chargeCard(userId, amount);
    dbSpan.end();

    span.setStatus({ code: SpanStatusCode.OK });
    return result;
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR });
    throw error;
  } finally {
    span.end();
  }
}
```

### Metrics (Counters, Gauges, Histograms)

```javascript
const { metrics } = require('@opentelemetry/api');
const meter = metrics.getMeter('my-service', '1.0.0');

// Counter — tăng thêm 1 mỗi lần
const paymentCounter = meter.createCounter('payment.requests', {
  description: 'Total payment requests',
});

// Gauge — đo giá trị tại thời điểm
const activeConnections = meter.createUpDownCounter('connections.active', {
  description: 'Active connections',
});

// Histogram — phân phối thời gian
const latencyHistogram = meter.createHistogram('payment.latency_ms', {
  description: 'Payment processing latency in ms',
});

// Sử dụng
paymentCounter.add(1, { 'payment.status': 'success' });
activeConnections.add(1);
latencyHistogram.record(150, { 'payment.method': 'card' });
```

---

## 3️⃣ OTel Collector

### Collector Architecture

```
Application → OTel Collector → Prometheus (metrics)
               ↓               → Jaeger (traces)
               ↓               → Loki (logs via Promtail)
```

### Docker Compose Setup

```yaml
version: '3.8'

services:
  # OTel Collector
  otel-collector:
    image: otel/opentelemetry-collector:latest
    command: ["--config=/etc/otel-collector-config.yaml"]
    ports:
      - "4318:4318"      # OTLP HTTP (application → collector)
      - "4317:4317"      # OTLP gRPC
      - "9411:9411"      # Zipkin
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
    depends_on:
      - prometheus
      - jaeger

  # Prometheus — lưu metrics
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"

  # Jaeger — lưu traces
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "6831:6831/udp"   # Jaeger agent
      - "16686:16686"     # Jaeger UI (localhost:16686)

  # Grafana — visualization
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    depends_on:
      - prometheus
```

### OTel Collector Config

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
  
  memory_limiter:
    check_interval: 1s
    limit_mib: 512

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"  # Prometheus scrapes từ đây
  
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true
  
  logging:  # debug: in ra stdout
    loglevel: debug

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [jaeger, logging]
    
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus, logging]
```

---

## 4️⃣ SLO/SLI/SLA Concepts

### SLA vs SLO vs SLI

| Khái Niệm | Định Nghĩa | Ví Dụ |
|-----------|-----------|-------|
| **SLA** (Service Level Agreement) | Hợp đồng giữa công ty & khách hàng — cam kết nào | "99.9% uptime hoặc hoàn tiền" |
| **SLO** (Service Level Objective) | Mục tiêu nội bộ — chúng ta muốn đạt được | "99.5% uptime tháng này" |
| **SLI** (Service Level Indicator) | Đo lường thực tế — cách đo SLO | Uptime = (successful_requests / total_requests) × 100 |

### SLO Examples

**Availability SLO:**
```
SLO: 99.5% availability
SLI: (successful_requests / total_requests) × 100
Goal: ≥ 99.5% trong tháng
Ngưỡng cảnh báo: < 99.0% → escalate
```

**Latency SLO:**
```
SLO: 95% requests < 500ms
SLI: percentile(request_latency, 0.95)
Goal: p95_latency < 500ms
Ngưỡng cảnh báo: p95 > 600ms → escalate
```

**Error Rate SLO:**
```
SLO: < 0.1% error rate
SLI: (error_requests / total_requests) × 100
Goal: < 0.1%
Ngưỡng cảnh báo: > 0.2% → escalate
```

### Error Budget

**Error Budget** = tổng lỗi mà có thể chấp nhận mà không vi phạm SLO:

```
99.5% uptime SLO = 0.5% error budget
Tháng 30 ngày = 43,200 phút
Error budget = 43,200 × 0.5% = 216 phút downtime được phép

Nếu hết error budget:
- Tắt feature flags chưa test
- Dừng deploy (freeze)
- Giảm tần suất deploy
```

---

## 5️⃣ Prometheus Fundamentals

### Prometheus Query Language (PromQL)

**Metrics Types:**
```
gauge      — giá trị tại một thời điểm (CPU, memory, connections)
counter    — chỉ tăng (requests, errors, bytes sent)
histogram  — phân phối (latency buckets)
summary    — percentiles (p50, p95, p99)
```

**Basic Queries:**

```promql
# Gauge: lấy giá trị hiện tại
node_memory_MemAvailable_bytes

# Counter: tỷ lệ thay đổi (requests/sec)
rate(http_requests_total[5m])

# Giá trị tuyệt đối (không rate)
http_requests_total

# With labels
http_requests_total{job="payment", status="200"}

# Aggregation
sum(rate(http_requests_total[5m])) by (job)

# Error rate (%)
(rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])) * 100

# Latency percentile (từ histogram)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Prometheus Config

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
  
  - job_name: 'payment-app'
    static_configs:
      - targets: ['payment-app:8080']
    metrics_path: '/metrics'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - 'alert-rules.yml'
```

---

## 6️⃣ Grafana Dashboards

### Grafana Data Source Setup

1. **Add Prometheus:**
   - Data Sources → Add Prometheus
   - URL: `http://prometheus:9090`

2. **Add Jaeger:**
   - Data Sources → Add Jaeger
   - URL: `http://jaeger:16686`

### Example Dashboard JSON

```json
{
  "dashboard": {
    "title": "Payment Service Observability",
    "panels": [
      {
        "title": "Request Rate (req/sec)",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{job=\"payment\"}[5m])) by (job)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Error Rate (%)",
        "targets": [
          {
            "expr": "(sum(rate(http_requests_total{job=\"payment\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"payment\"}[5m]))) * 100"
          }
        ],
        "type": "stat",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {"color": "green", "value": null},
            {"color": "red", "value": 1}
          ]
        }
      },
      {
        "title": "P95 Latency (ms)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"payment\"}[5m])) * 1000"
          }
        ],
        "type": "gauge",
        "max": 1000
      }
    ]
  }
}
```

---

## 7️⃣ Loki for Logs

### Loki Architecture

```
Application Logs → Promtail (log shipper) → Loki → Grafana
```

### Promtail Config

```yaml
# promtail-config.yml
server:
  http_listen_port: 3101
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: payment-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: payment
          __path__: /var/log/payment/*.log
    pipeline_stages:
      - json:
          timestamp:
            parse_from: time
            layout: 2006-01-02T15:04:05Z07:00
          level:
            parse_from: level
          trace_id:
            parse_from: trace_id
      - labels:
          level:
          trace_id:
```

### LogQL (Loki Query Language)

```logql
# Tất cả logs từ payment service
{job="payment"}

# Logs với error level
{job="payment"} | json | level="ERROR"

# Logs match trace_id
{job="payment"} | json trace_id="abc123xyz"

# Metrics từ logs (rate)
rate({job="payment"} | json level="ERROR" [5m])

# Pattern matching
{job="payment"} |= "Failed to charge"
```

---

## 8️⃣ Multi-Window Burn Rate Alerts

### Burn Rate Concept

```
Error Budget (99.5% SLO): 0.5% per month
If we burn 10× the budget per hour:
  — Fast window: if 10% error rate for 1h → burn 10×
  — Slow window: if 2% error rate for 6h → burn 10×
→ Trigger alert → Team handles urgently

Burn Rate = (error_rate / error_budget) 
```

### Alert Rules (Prometheus)

```yaml
# alert-rules.yml
groups:
  - name: payment_slo_alerts
    interval: 1m
    
    rules:
      # Fast burn: 10% error rate for 5 minutes
      - alert: HighErrorRateFast
        expr: |
          (sum(rate(http_requests_total{job="payment", status=~"5.."}[5m])) /
           sum(rate(http_requests_total{job="payment"}[5m]))) > 0.10
        for: 5m
        labels:
          severity: critical
          burn_window: fast
        annotations:
          summary: "Payment service has 10%+ error rate (fast burn)"
          runbook: "https://wiki/payment/high-error-fast"
      
      # Slow burn: 2% error rate for 30 minutes
      - alert: HighErrorRateSlow
        expr: |
          (sum(rate(http_requests_total{job="payment", status=~"5.."}[30m])) /
           sum(rate(http_requests_total{job="payment"}[30m]))) > 0.02
        for: 30m
        labels:
          severity: warning
          burn_window: slow
        annotations:
          summary: "Payment service has 2%+ error rate (slow burn)"
          runbook: "https://wiki/payment/high-error-slow"
      
      # Availability SLO: 99.5%
      - alert: AvailabilitySLOViolation
        expr: |
          (sum(rate(http_requests_total{job="payment", status="200"}[5m])) /
           sum(rate(http_requests_total{job="payment"}[5m]))) < 0.995
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Payment availability below 99.5%"
      
      # Latency SLO: p95 < 500ms
      - alert: LatencySLOViolation
        expr: |
          histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="payment"}[5m])) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Payment p95 latency exceeds 500ms"
```

### Multi-Window Table (Google SRE)

```
┌─────────────┬──────────┬──────────────┐
│ Alert Level │ Window   │ Burn Rate    │
├─────────────┼──────────┼──────────────┤
│ Critical    │ 1h       │ > 6%/hour    │
│ (Page)      │ × 5m     │ (error bgt)  │
├─────────────┼──────────┼──────────────┤
│ Warning     │ 6h       │ > 3%/6hour   │
│ (Alert)     │ × 30m    │ (error bgt)  │
└─────────────┴──────────┴──────────────┘

Nếu alert Critical → Page on-call (immediate action)
Nếu alert Warning → Log, review trong standup
```

---

## 9️⃣ Ví Dụ Thực Hành

### Lab 1: Thiết Lập OTel Collector + Prometheus + Grafana

**Step 1: Docker Compose (từ phần 3)**
```bash
cd W9/cloud/w9/day-b
docker-compose up -d
```

**Step 2: Instrument Node.js App**
```bash
npm install @opentelemetry/api @opentelemetry/sdk-node \
            @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-trace-otlp-http \
            @opentelemetry/exporter-metrics-otlp-http
```

**Step 3: Verify trong Prometheus**
- Truy cập: http://localhost:9090
- Query: `up{job="otel-collector"}`
- Kết quả: metric từ collector

**Step 4: Verify trong Jaeger**
- Truy cập: http://localhost:16686
- Chọn service: `payment`
- Xem traces

**Step 5: Create Grafana Dashboard**
- Truy cập: http://localhost:3000
- Add Prometheus data source
- Create panel từ PromQL queries

### Lab 2: SLO Calculation & Alerts

**Step 1: Define SLO**
```yaml
# slo-definition.yaml
service: payment
objectives:
  - name: availability
    target: 99.5
    indicator: (successful_requests / total_requests) × 100
  
  - name: latency
    target: 95
    indicator: p95_latency_ms < 500
    
  - name: error_rate
    target: 0.1
    indicator: error_rate_percent < 0.1
```

**Step 2: Create Alert Rules**
- Copy alert rules từ phần 8️⃣
- Apply: `kubectl apply -f alert-rules.yml`

**Step 3: Simulate Load & Monitor**
```bash
# Terminal 1: Generate load
k6 run load-test.js --vus 10 --duration 5m

# Terminal 2: Watch Prometheus alerts
curl http://localhost:9090/api/v1/alerts
```

---

## 🔟 Những Điểm Chính


1. **OpenTelemetry unified** cho traces, metrics, logs
   - OTel SDK auto-instrument ứng dụng
   - Exporter gửi tới backend
   - Vendor-neutral (không khóa nhà cung cấp)

2. **SLO/SLI/SLA framework** để đo lường chất lượng dịch vụ
   - SLI = cách đo (ví dụ: request success rate)
   - SLO = mục tiêu (ví dụ: 99.5% success)
   - SLA = hợp đồng (ví dụ: hoàn tiền nếu không đạt)

3. **Error Budget** là động lực để thúc đẩy tự động hóa
   - Không error budget → freeze deploy → pressure → CI/CD automation
   - Có error budget → deploy slowly but steadily

4. **Prometheus + Grafana + Loki** = observability stack hoàn chỉnh
   - Prometheus: metrics (time-series)
   - Grafana: visualization
   - Loki: logs (structured)

5. **Multi-window burn rate alerts** để phát hiện vấn đề sớm
   - Fast window (5m × 1h): immediate action
   - Slow window (30m × 6h): trending problem
   - Kết hợp → confident escalation

### 🎯 Bước Tiếp Theo (D3)

- Argo Rollouts: canary deployment
- AnalysisTemplate: metric queries for abort
- Integrate burn rate alerts với canary abort

### 📚 Tài Nguyên Tham Khảo

- OpenTelemetry Docs: https://opentelemetry.io/docs
- Prometheus Docs: https://prometheus.io/docs
- Grafana Docs: https://grafana.com/docs/grafana/latest
- Loki Docs: https://grafana.com/docs/loki/latest
- Google SRE Book: https://sre.google/sre-book/service-level-objectives
- Google SRE Workbook: https://sre.google/workbook/implementing-slos



