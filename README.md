# O-RAN Telemetry Demo with Expanso on OpenShift

Demo showing Expanso Edge pipeline consuming O-RAN metrics and pushing to OTEL Collector on OpenShift.

**[Landing Page](https://aronchick.github.io/oran-sample/)** | **[Quick Start Guide](https://aronchick.github.io/oran-sample/quickstart.html)**

## Overview

This demo showcases how [Expanso](https://expanso.io) can collect, transform, and route O-RAN telemetry data from edge Distributed Units (DUs) running on OpenShift Single Node deployments. The pipeline transforms raw DU metrics into OpenTelemetry Protocol (OTLP) format for ingestion by any OTLP-compatible observability backend.

### Key Capabilities

- **Edge-native processing** - Runs directly on SNO nodes with minimal footprint
- **Real-time transformation** - Bloblang processors normalize and enrich telemetry
- **Multi-destination routing** - Fan-out to multiple OTLP endpoints simultaneously
- **Cloud-managed pipelines** - Deploy and update pipelines via Expanso Cloud

## Red Hat Integration

This demo is designed for integration with Red Hat's observability stack:

- **OpenShift Container Platform** (Single Node deployment)
- **OpenTelemetry Collector** (metrics routing)
- **Red Hat Observability** or any OTLP-compatible backend

## Expanso Pipeline Architecture

Expanso Edge pipelines follow an Input → Processors → Output model:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Expanso Edge Pipeline                      │
│                                                                 │
│   ┌─────────┐     ┌─────────────────────┐     ┌─────────────┐  │
│   │  INPUT  │────▶│     PROCESSORS      │────▶│   OUTPUT    │  │
│   │         │     │                     │     │             │  │
│   │ - file  │     │ - transform         │     │ - HTTP      │  │
│   │ - http  │     │ - filter            │     │ - OTLP      │  │
│   │ - kafka │     │ - enrich            │     │ - Kafka     │  │
│   │ - generate│   │ - validate          │     │ - stdout    │  │
│   └─────────┘     └─────────────────────┘     └─────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Pipeline Configuration (Bloblang)

The pipeline uses Bloblang for data transformation. Key patterns:

```yaml
pipeline:
  processors:
    - mapping: |
        # Transform raw metrics to OTLP format
        let ts = (this.timestamp * 1000000000).string()

        root.resourceMetrics = [{
          "resource": {
            "attributes": [
              {"key": "service.name", "value": {"stringValue": "du-simulator"}},
              {"key": "du.id", "value": {"stringValue": this.du_id}}
            ]
          },
          "scopeMetrics": [{
            "scope": {"name": "du-telemetry", "version": "1.0.0"},
            "metrics": [
              {
                "name": "du.ptp4l_offset_ns",
                "unit": "ns",
                "gauge": {
                  "dataPoints": [{"timeUnixNano": $ts, "asInt": this.ptp4l_offset_ns}]
                }
              }
            ]
          }]
        }]
```

## Demo Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        OpenShift Single Node (Edge Site)                     │
│                                                                              │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐        │
│  │  O-RAN Metrics  │────▶│  Expanso Edge   │────▶│  OTEL Collector │        │
│  │  (DU Simulator) │     │  (Pipeline)     │     │                 │        │
│  └─────────────────┘     └─────────────────┘     └────────┬────────┘        │
│         INPUT              PROCESSORS              OUTPUT  │                 │
│                            - transform to OTLP            │                  │
│                                                           ▼                  │
│                          ┌─────────────────┐     ┌─────────────────┐        │
│                          │     Grafana     │◀────│   Prometheus    │        │
│                          └─────────────────┘     └─────────────────┘        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Input**: DU simulator generates O-RAN telemetry every 5 seconds
2. **Processing**: Bloblang transforms metrics to OTLP JSON format
3. **Output**: HTTP POST to OTEL Collector at `/v1/metrics`
4. **Storage**: Prometheus scrapes OTEL Collector's Prometheus exporter
5. **Visualization**: Grafana queries Prometheus for dashboards

## Multi-Destination Output

The pipeline can fan-out to multiple OTLP Collectors:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        OpenShift Single Node (Edge Site)                     │
│                                                                              │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐        │
│  │  O-RAN Metrics  │────▶│  Expanso Edge   │──┬─▶│  OTEL Collector │        │
│  │  (DU Simulator) │     │  (Pipeline)     │  │  │  (local)        │        │
│  └─────────────────┘     └─────────────────┘  │  └─────────────────┘        │
│         INPUT              PROCESSORS         │                              │
│                                               │                              │
└───────────────────────────────────────────────┼──────────────────────────────┘
                                                │
                                                │ OUTPUT (multiple destinations)
                                                ▼
                                      ┌─────────────────┐
                                      │  OTEL Collector │
                                      │  (external/cloud)│
                                      └─────────────────┘
```

This enables:
- **Local observability** for on-site operators
- **Central aggregation** for fleet-wide visibility
- **Hybrid routing** based on metric criticality

## O-RAN Metrics

The demo simulates key O-RAN DU telemetry:

| Metric | Unit | Description |
|--------|------|-------------|
| `du.ptp4l_offset_ns` | nanoseconds | PTP clock offset from grandmaster |
| `du.cpu_pct` | percent | CPU utilization on isolated cores |
| `du.prb_dl_pct` | percent | Physical Resource Block utilization (downlink) |

### PTP Compliance Thresholds

Per O-RAN and Red Hat RAN Reference Design specifications:

| Metric | Threshold | Status |
|--------|-----------|--------|
| ptp4l offset | ±100ns | DEGRADED if exceeded |
| phc2sys offset | ±50ns | DEGRADED if exceeded |
| Lock state | != LOCKED | CRITICAL |

## Prerequisites

- **OpenShift cluster** - Single Node OpenShift (SNO) or standard cluster
- **oc CLI** - Logged in with permissions to create deployments, services, routes
- **Expanso Cloud account** - Register at [cloud.expanso.io](https://cloud.expanso.io)

### OpenShift Requirements

```bash
# Verify cluster access
oc whoami
oc get nodes

# Ensure you have a project/namespace
oc project <your-project>
```

## Deployment

### Step 1: Register Node with Expanso Cloud

Create your Expanso Cloud account and set up credentials for the edge node.

1. Go to [cloud.expanso.io](https://cloud.expanso.io)
2. Create a new **Network** (logical grouping of edge nodes)
3. Generate a **bootstrap token** - this authenticates the edge node

> **Note**: The bootstrap token is a one-time credential. Store it securely.

### Step 2: Create Bootstrap Secret

Store the bootstrap token as a Kubernetes secret:

```bash
oc create secret generic expanso-bootstrap \
  --from-literal=token=<BOOTSTRAP_TOKEN>
```

Verify the secret:

```bash
oc get secret expanso-bootstrap -o yaml
```

### Step 3: Deploy Observability Stack

Deploy the OTEL Collector, Prometheus, and Grafana:

```bash
oc apply -f observability-deployment.yaml
```

This creates:
- **OTEL Collector** - Receives OTLP metrics, exports to Prometheus format
- **Prometheus** - Scrapes OTEL Collector, stores time-series data
- **Grafana** - Visualization and dashboards

Verify pods are running:

```bash
oc get pods -w
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
otel-collector-xxxxxxxxx-xxxxx    1/1     Running   0          30s
prometheus-xxxxxxxxx-xxxxx        1/1     Running   0          30s
grafana-xxxxxxxxx-xxxxx           1/1     Running   0          30s
```

### Step 4: Deploy Expanso Edge

Deploy the Expanso Edge agent:

```bash
oc apply -f expanso-edge-deployment.yaml
```

The agent will:
1. Read the bootstrap token from the secret
2. Register itself with Expanso Cloud
3. Begin polling for pipeline configurations

Verify registration:
```bash
oc logs -f deployment/expanso-edge
```

### Step 5: Apply Pipeline via Expanso Cloud

Deploy the pipeline through Expanso Cloud:

1. Go to [cloud.expanso.io](https://cloud.expanso.io)
2. Navigate to your Network
3. Click **Create Pipeline**
4. Paste the contents of `expanso-pipeline-FOR-EXPANSO-CLOUD.yaml`
5. Click **Deploy**

The pipeline will be pushed to all nodes in the network.

### Step 6: View Metrics in Grafana

Access the Grafana dashboard:

```bash
# Get the route URL
oc get route grafana -o jsonpath='{.spec.host}'
```

1. Open the URL in your browser
2. Login with `admin` / `admin`
3. Go to **Explore** → Select **Prometheus** datasource
4. Query metrics:
   - `du_ptp4l_offset_ns`
   - `du_cpu_pct`
   - `du_prb_dl_pct`

## Files Reference

| File | Description |
|------|-------------|
| `observability-deployment.yaml` | OTEL Collector, Prometheus, Grafana stack |
| `expanso-edge-deployment.yaml` | Expanso Edge agent deployment |
| `expanso-pipeline-FOR-EXPANSO-CLOUD.yaml` | Pipeline config (for Expanso Cloud UI) |
| `expanso-pipeline-FOR-EXPANSO-CLI.yaml` | Pipeline config (for CLI deployment) |

### YAML Structure

**observability-deployment.yaml**:
```yaml
# ConfigMaps for OTEL Collector and Prometheus
# Deployments for all three services
# Services for internal communication
# Route for Grafana external access
```

**expanso-edge-deployment.yaml**:
```yaml
# Deployment with bootstrap token from secret
# Service for Expanso Edge API (port 9010)
# Route for external access (optional)
```

## Troubleshooting

### Pipeline not receiving data

```bash
# Check Expanso Edge logs
oc logs deployment/expanso-edge

# Check OTEL Collector logs
oc logs deployment/otel-collector

# Verify services are running
oc get svc
```

### Metrics not appearing in Grafana

```bash
# Check Prometheus targets
oc port-forward svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Verify OTEL Collector is exporting
oc port-forward svc/otel-collector 8889:8889
curl http://localhost:8889/metrics
```

### Bootstrap token issues

```bash
# Verify secret exists
oc get secret expanso-bootstrap

# Check token value (base64 encoded)
oc get secret expanso-bootstrap -o jsonpath='{.data.token}' | base64 -d
```

## Cleanup

Remove all deployed resources:

```bash
oc delete -f expanso-edge-deployment.yaml
oc delete -f observability-deployment.yaml
oc delete secret expanso-bootstrap
```

## Learn More

- [Expanso Documentation](https://docs.expanso.io)
- [Expanso Cloud](https://cloud.expanso.io)
- [OpenTelemetry Protocol Specification](https://opentelemetry.io/docs/specs/otlp/)
- [O-RAN Alliance](https://www.o-ran.org/)
