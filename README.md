# O-RAN Telemetry Demo with Expanso on OpenShift

Demo showing Expanso Edge pipeline consuming O-RAN metrics and pushing to OTEL Collector on OpenShift.

**[Quick Start Guide](https://aronchick.github.io/oran-sample/landing.html)** | **[Full Documentation](https://aronchick.github.io/oran-sample/)**

## Red Hat Integration

This demo is designed for integration with Red Hat's observability stack:

- **OpenShift Container Platform** (Single Node deployment)
- **OpenTelemetry Collector** (metrics routing)
- **Red Hat Observability** or any OTLP-compatible backend

## Expanso Pipeline

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
│   │ - etc.  │     │ - etc.              │     │ - etc.      │  │
│   └─────────┘     └─────────────────────┘     └─────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Architecture (This Demo)

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

## Multi-Destination Output

The pipeline can also push to external OTEL Collectors outside OpenShift:

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
                                      │  (external)     │
                                      └─────────────────┘
```

## What This Demonstrates

- **Expanso Edge pipeline**: Input → Processors → Output
- **Consuming** O-RAN DU metrics (input)
- **Transforming** to OTLP format (processors)
- **Pushing** to OTEL Collectors (output) - local and/or external

## Prerequisites

- OpenShift cluster (user provides)
- Logged in via `oc` CLI
- Expanso Cloud account at [cloud.expanso.io](https://cloud.expanso.io) (for node registration)

## Deployment

### Step 1: Register Node with Expanso Cloud

Set up your Expanso Cloud account and create credentials for the edge node.

1. Go to [cloud.expanso.io](https://cloud.expanso.io)
2. Create a new Network.
3. Create a new bootstrap token. This token is essential for the next steps.

### Step 2: Create Bootstrap Secret

Store the bootstrap token as a Kubernetes secret for Expanso Edge to use.

```bash
oc create secret generic expanso-bootstrap \
  --from-literal=token=<BOOTSTRAP_TOKEN>
```

### Step 3: Deploy Observability Stack

Deploy the OTEL Collector, Prometheus, and Grafana to receive and visualize metrics.

```bash
oc apply -f observability-deployment.yaml
```

Verify pods are running:

```bash
oc get pods
```

### Step 4: Deploy Expanso Edge

Deploy Expanso Edge node as a Pod. It will register itself with Expanso Cloud using the bootstrap token.

```bash
oc apply -f expanso-edge-deployment.yaml
```

### Step 5: Apply Pipeline via Expanso Cloud

Create and run the pipeline from Expanso Cloud.

1. Go to [cloud.expanso.io](https://cloud.expanso.io)
2. Navigate to the Network you created in Step 1
3. Create a new pipeline with the content of `expanso-pipeline.yaml`
4. Run the pipeline

### Step 6: View Metrics in Grafana

Access Grafana to see the O-RAN metrics flowing through the pipeline.

```bash
oc get route grafana
```

Open the route URL in your browser. Login with `admin` / `admin`.

Go to the **Explore** menu and query for the metrics (e.g., `du_cpu_pct`, `du_prb_dl_pct`, `du_ptp4l_offset_ns`).

## Files

| File | Description |
|------|-------------|
| `observability-deployment.yaml` | OTEL Collector, Prometheus, Grafana |
| `expanso-edge-deployment.yaml` | Expanso Edge pod deployment |
| `expanso-pipeline.yaml` | Pipeline configuration (applied via Expanso Cloud) |

## Cleanup

```bash
oc delete -f expanso-edge-deployment.yaml
oc delete -f observability-deployment.yaml
```
