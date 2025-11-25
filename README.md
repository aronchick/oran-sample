# O-RAN Telemetry Pipeline

An Expanso pipeline for processing O-RAN (Open Radio Access Network) telemetry data from OpenShift-deployed Distributed Units (DUs).

## Quick Start

### 1. Install the CLI

```bash
curl -fsSL https://get.expanso.io/cli/install.sh | sh
```

The CLI (`expanso-cli`) manages your control plane and orchestrates deployments.

### 2. Install the Edge Agent

```bash
curl -sL https://get.expanso.io/edge/install.sh | bash
```

The Edge agent (`expanso-edge`) runs pipelines locally or at edge locations.

### 3. Local Development Workflow

The recommended way to develop and test pipelines is to run both components locally. The Edge agent exposes an API that the CLI can connect to for deploying and managing jobs.

**Terminal 1 - Start the Edge agent:**
```bash
expanso-edge
```

This starts the agent with its API listening on `localhost:9010`.

**Terminal 2 - Deploy and manage jobs via CLI:**
```bash
# Point CLI at local edge agent
export EXPANSO_CLI_ENDPOINT=http://localhost:9010

# Deploy your pipeline as a job
expanso-cli job deploy pipeline.yaml --force -v

# Check job status
expanso-cli job list
expanso-cli job describe oran-sample-pipeline

# View executions
expanso-cli execution list
```

The `--force` flag redeploys even if the job already exists. Use `-v` for verbose output during development.

### 4. Run a Pipeline Directly (Standalone)

For quick testing without the CLI, you can run a pipeline file directly:

```bash
expanso-edge run pipeline.yaml
```

This bypasses the job scheduler and runs the pipeline immediately in the foreground.

### 5. Connect to the Cloud

1. Create your control plane at https://cloud.expanso.io and get your API token
2. Save a profile to connect:
   ```bash
   expanso-cli profile save prod \
     --endpoint api.expanso.io \
     --token YOUR_TOKEN \
     --select
   ```
3. List available edge nodes (you can see all this in the UI!):
   ```bash
   expanso-cli node list
   ```
4. Deploy a job to the cluster:
   ```bash
   expanso-cli job deploy pipeline.yaml
   ```
5. Check job status and executions:
   ```bash
   expanso-cli job describe oran-sample-pipeline
   expanso-cli execution list --job oran-sample-pipeline
   ```

## Key Concepts

- **Profiles**: Connection configurations for different Expanso environments
- **Jobs**: Pipeline specifications that run on edge nodes
- **Nodes**: Edge agents connected to the control plane
- **Evaluations**: Scheduler decisions about job assignment
- **Executions**: Job instances running on specific nodes

## Pipeline Architecture

The pipeline (`pipeline.yaml`) performs:

1. **Data Generation**: Simulates O-RAN DU telemetry including:
   - PTP (Precision Time Protocol) synchronization status
   - SR-IOV network interface statistics
   - FEC accelerator metrics
   - CPU isolation configuration

2. **Processing**: Normalizes and validates telemetry data:
   - PTP compliance checking (offsets, lock state)
   - Interface health scoring
   - RT kernel validation per Red Hat RAN specs

3. **Routing**: Outputs to separate files based on sync health:
   - Critical/degraded alerts → `/tmp/critical.txt`
   - Normal data → `/tmp/normal.txt`

## PTP Thresholds

- PTP offset: ±100ns triggers DEGRADED_OFFSET_HIGH
- System clock offset: ±50ns triggers DEGRADED_SYS_CLOCK
- Lock state != LOCKED triggers CRITICAL_UNLOCK
- SFP temperature >70°C flagged as HOT

## What you just saw!

* Creating a new node on your Expanso cluster
* Deploying a pipeline to local (for testing)
* Having that pipeline generate fake data, and then splitting the output of that data.
* Deploying a pipeline to the cloud (for production)
* Seeing that pipeline run on your local machine

## What you DIDN'T see!

* Deploying this as a container or via a helm chart to K3s/OpenShift (but it should be trivial)
