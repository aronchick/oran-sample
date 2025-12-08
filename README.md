# O-RAN Telemetry Pipeline

[![CI - Validate Pipelines](https://github.com/aronchick/oran-sample/actions/workflows/ci.yml/badge.svg)](https://github.com/aronchick/oran-sample/actions/workflows/ci.yml)
[![Deploy to GitHub Pages](https://github.com/aronchick/oran-sample/actions/workflows/pages.yml/badge.svg)](https://github.com/aronchick/oran-sample/actions/workflows/pages.yml)

**[View Demo Site](https://aronchick.github.io/oran-sample/)**

An Expanso pipeline for processing O-RAN (Open Radio Access Network) telemetry data from OpenShift-deployed Distributed Units (DUs). Outputs via **OTLP** for integration with Red Hat Observability and other OpenTelemetry-compatible backends.

## Quick Start

**Step 1: Start the demo**

```bash
./demo.sh local
```

**Step 2: View the metrics (in a NEW terminal)**

```bash
tail -f /tmp/oran-metrics.log
```

You'll see output like this every 5 seconds:

```
[10:25:03] ▶ Received 14 metrics from DU-SNO-DEMO-0
[10:25:03]   ● sync_health: HEALTHY
[10:25:03]   ◦ ptp4l_offset_ns: 42
[10:25:03]   ◦ ens1f0 temp: 51°C
[10:25:03]   ◦ ens1f1 temp: 48°C
[10:25:08] ▶ Received 14 metrics from DU-SNO-DEMO-1
[10:25:08]   ● sync_health: DEGRADED_OFFSET_HIGH
[10:25:08]   ◦ ptp4l_offset_ns: 127
...
```

**Step 3: Stop**

Press `Ctrl+C` in the first terminal.

## How to Run

| Command | What it does | Where to view output |
|---------|--------------|----------------------|
| `./demo.sh local` | Runs pipeline + mock OTLP receiver | `tail -f /tmp/oran-metrics.log` |
| `./demo.sh local-grafana` | Runs pipeline + Grafana/Prometheus | http://localhost:3000 (admin/admin) |
| `./demo.sh openshift` | Deploys to OpenShift cluster | Your OTLP backend |
| `./demo.sh clean` | Kills processes, cleans up | N/A |

## Viewing Output

| Mode | Log Location | How to View |
|------|--------------|-------------|
| `./demo.sh local` | `/tmp/oran-metrics.log` | `tail -f /tmp/oran-metrics.log` |
| `./demo.sh local-grafana` | Grafana dashboards | Open http://localhost:3000 |
| Manual with `pipeline.yaml` | `/tmp/normal.txt`, `/tmp/critical.txt` | `tail -f /tmp/normal.txt` |
| Manual with `pipeline-otlp.yaml` | Your OTLP receiver | Check your observability backend |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              OpenShift Single Node (Edge Site)                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Expanso Edge Agent                      │ │
│  │                                                            │ │
│  │  O-RAN DU Telemetry    Bloblang         OTLP/HTTP         │ │
│  │  ┌─────────────┐  ──▶  Processing  ──▶  ┌─────────────┐   │ │
│  │  │ PTP Sync    │       (normalize,      │ Configurable│   │ │
│  │  │ SR-IOV NICs │        validate,       │  Endpoint   │───┼─┼──▶ Any OTLP Backend
│  │  │ FEC Accel   │        enrich)         │             │   │ │
│  │  └─────────────┘                        └─────────────┘   │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Installation (Prerequisites)

```bash
# Install the Expanso Edge Agent
curl -sL https://get.expanso.io/edge/install.sh | bash
```

## Manual Running (Advanced)

If you want to run without the demo script:

```bash
# Option 1: Output to files (simplest, no OTLP receiver needed)
expanso-edge run pipeline.yaml --local

# Option 2: Output to OTLP (you must have an OTLP receiver running)
OTLP_ENDPOINT=http://your-receiver:4318 expanso-edge run pipeline-otlp.yaml --local
```

**Important flags:**
- `--local` - Run in standalone mode (no cloud connection required)
- `--data-dir ./mydata` - Use a custom data directory (avoids conflicts)

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `OTLP_ENDPOINT` | `http://localhost:4318` | OTLP HTTP receiver URL |
| `EMIT_INTERVAL` | `5s` | Telemetry emission interval |
| `NODE_NAME` | `du-sno-worker` | DU node identifier |
| `CLUSTER_NAME` | `sno-edge-01` | OpenShift cluster name |

## OTLP Metrics

The pipeline emits the following metrics in OTLP format:

### PTP Synchronization
- `oran.ptp.ptp4l_offset_ns` - Clock offset from grandmaster (ns)
- `oran.ptp.phc2sys_offset_ns` - System clock offset (ns)
- `oran.ptp.clock_class` - PTP clock class (6 = locked)
- `oran.sync_health` - Overall sync status (0=healthy, 1=degraded, 2=critical)

### SR-IOV Interfaces
- `oran.interface.rx_packets` - Received packets (per interface)
- `oran.interface.dropped` - Dropped packets (per interface)
- `oran.interface.sfp_temperature_c` - SFP module temperature

### FEC Accelerator
- `oran.fec.utilization_pct` - Accelerator utilization
- `oran.fec.queue_depth` - Queue depth

### Compute
- `oran.compute.cpu_usage_pct` - CPU usage on isolated cores

All metrics include resource attributes: `k8s.node.name`, `k8s.cluster.name`, `ptp.gm_identity`, `oran.profile`

## PTP Compliance Thresholds

Per Red Hat RAN Reference Design specifications:

| Metric | Threshold | Status |
|--------|-----------|--------|
| ptp4l offset | ±100ns | DEGRADED_OFFSET_HIGH |
| phc2sys offset | ±50ns | DEGRADED_SYS_CLOCK |
| Lock state | != LOCKED | CRITICAL_UNLOCK |
| SFP temperature | >70°C | HOT |

## File Structure

```
├── pipeline.yaml           # File output (development)
├── pipeline-otlp.yaml      # OTLP output (production)
├── demo.sh                 # Demo/deployment script
├── deploy/
│   └── openshift/          # OpenShift Kustomize manifests
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── configmap.yaml
│       └── deployment.yaml
├── docs/
│   └── index.html          # Landing page (GitHub Pages)
├── scripts/
│   └── setup-dev.sh        # Development environment setup
└── .github/
    └── workflows/
        ├── ci.yml          # Pipeline validation CI
        └── pages.yml       # GitHub Pages deployment
```

## Development

### Setup

```bash
# Install pre-commit hooks and Expanso CLI
./scripts/setup-dev.sh
```

This installs:
- **pre-commit**: Runs validation on every commit
- **expanso-cli**: Validates pipeline YAML syntax

### Validation

Pipelines are validated automatically:
- **On commit**: Pre-commit hooks run `expanso-cli job validate`
- **On push/PR**: GitHub Actions CI validates all pipelines
- **Manually**: `expanso-cli job validate pipeline-otlp.yaml`

## What's New

- **OTLP Output**: Native OpenTelemetry Protocol support for metrics
- **OpenShift Deployment**: Kustomize manifests for SNO deployment
- **Configurable Endpoint**: Point to any OTLP-compatible backend
- **Demo Script**: One-command local testing with mock receiver or full Grafana stack

## Red Hat Integration

This pipeline is designed for integration with Red Hat's observability stack:
- **OpenShift Container Platform** (Single Node deployment)
- **OpenTelemetry Collector** (metrics routing)
- **Red Hat Observability** or any OTLP-compatible backend

See the [landing page](docs/index.html) for more details on the Expanso + Red Hat partnership.
