#!/usr/bin/env bash
#
# Expanso O-RAN Demo Script
# -------------------------
# Demonstrates O-RAN telemetry collection with OTLP output
#
# Usage:
#   ./demo.sh local          # Run locally with mock OTLP receiver
#   ./demo.sh local-grafana  # Run locally with Grafana stack
#   ./demo.sh openshift      # Deploy to OpenShift
#   ./demo.sh clean          # Clean up resources
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
OTLP_PORT="${OTLP_PORT:-4318}"
OTLP_ENDPOINT="${OTLP_ENDPOINT:-http://localhost:${OTLP_PORT}}"
EMIT_INTERVAL="${EMIT_INTERVAL:-5s}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/.data"

# Print banner
print_banner() {
    echo -e "${PURPLE}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║   ███████╗██╗  ██╗██████╗  █████╗ ███╗   ██╗███████╗ ██████╗   ║
    ║   ██╔════╝╚██╗██╔╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██╔═══██╗  ║
    ║   █████╗   ╚███╔╝ ██████╔╝███████║██╔██╗ ██║███████╗██║   ██║  ║
    ║   ██╔══╝   ██╔██╗ ██╔═══╝ ██╔══██║██║╚██╗██║╚════██║██║   ██║  ║
    ║   ███████╗██╔╝ ██╗██║     ██║  ██║██║ ╚████║███████║╚██████╔╝  ║
    ║   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝   ║
    ║                                                           ║
    ║            O-RAN Edge Observability Demo                  ║
    ║                  + Red Hat OpenShift                      ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Print step
step() {
    echo -e "\n${BLUE}▶${NC} ${BOLD}$1${NC}"
}

# Print success
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print warning
warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Print error
error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
check_prereqs() {
    step "Checking prerequisites..."

    local missing=()

    if ! command -v expanso-edge &> /dev/null; then
        missing+=("expanso-edge")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install Expanso Edge:"
        echo "  curl -sL https://get.expanso.io/edge/install.sh | bash"
        exit 1
    fi

    success "All prerequisites met"
}

# Check OpenShift prerequisites
check_openshift_prereqs() {
    step "Checking OpenShift prerequisites..."

    if ! command -v oc &> /dev/null && ! command -v kubectl &> /dev/null; then
        error "Neither 'oc' nor 'kubectl' found"
        echo "Install OpenShift CLI: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
        exit 1
    fi

    # Check if logged in
    if command -v oc &> /dev/null; then
        if ! oc whoami &> /dev/null; then
            error "Not logged into OpenShift. Run: oc login"
            exit 1
        fi
        success "Logged into OpenShift as $(oc whoami)"
    fi
}

# Start mock OTLP receiver (prints received metrics)
start_mock_otlp() {
    step "Starting mock OTLP receiver on port ${OTLP_PORT}..."

    # Simple Python HTTP server that accepts OTLP and writes to log file
    # Metrics are written to /tmp/oran-metrics.log for easy viewing
    METRICS_LOG="/tmp/oran-metrics.log"
    : > "$METRICS_LOG"  # Clear the log file

    python3 -u << 'PYTHON' &
import http.server
import json
import os
from datetime import datetime

METRICS_LOG = "/tmp/oran-metrics.log"

def log(msg):
    """Write to both stdout and log file"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line, flush=True)
    with open(METRICS_LOG, "a") as f:
        f.write(line + "\n")

class OTLPHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)

            for rm in data.get('resourceMetrics', []):
                resource = rm.get('resource', {})
                attrs = {a['key']: list(a['value'].values())[0] for a in resource.get('attributes', [])}
                node = attrs.get('k8s.node.name', 'unknown')

                for sm in rm.get('scopeMetrics', []):
                    metrics = sm.get('metrics', [])
                    log(f"▶ Received {len(metrics)} metrics from {node}")

                    for m in metrics:
                        name = m.get('name', '')
                        if 'sync_health' in name:
                            dp = m.get('gauge', {}).get('dataPoints', [{}])[0]
                            status = next((a['value']['stringValue'] for a in dp.get('attributes', []) if a['key'] == 'status'), 'unknown')
                            log(f"  ● sync_health: {status}")
                        elif 'ptp4l_offset' in name:
                            dp = m.get('gauge', {}).get('dataPoints', [{}])[0]
                            val = dp.get('asInt', 'N/A')
                            log(f"  ◦ ptp4l_offset_ns: {val}")
                        elif 'sfp_temperature' in name:
                            dp = m.get('gauge', {}).get('dataPoints', [{}])[0]
                            val = dp.get('asDouble', 'N/A')
                            iface = next((a['value']['stringValue'] for a in dp.get('attributes', []) if a['key'] == 'interface'), '?')
                            log(f"  ◦ {iface} temp: {val}°C")

        except Exception as e:
            log(f"⚠ Parse error: {e}")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{}')

port = int(os.environ.get('OTLP_PORT', 4318))
server = http.server.HTTPServer(('0.0.0.0', port), OTLPHandler)
log(f"Mock OTLP receiver listening on port {port}")
server.serve_forever()
PYTHON

    MOCK_PID=$!
    echo $MOCK_PID > /tmp/expanso-mock-otlp.pid
    sleep 1

    if kill -0 $MOCK_PID 2>/dev/null; then
        success "Mock OTLP receiver started (PID: $MOCK_PID)"
    else
        error "Failed to start mock OTLP receiver"
        exit 1
    fi
}

# Run pipeline locally
run_local() {
    check_prereqs

    step "Starting O-RAN telemetry pipeline..."
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "    OTLP Endpoint: ${PURPLE}${OTLP_ENDPOINT}${NC}"
    echo -e "    Emit Interval: ${EMIT_INTERVAL}"
    echo ""

    # Start mock receiver if endpoint is localhost
    if [[ "$OTLP_ENDPOINT" == *"localhost"* ]]; then
        start_mock_otlp
    fi

    # Start edge agent with API enabled
    step "Starting Expanso Edge agent..."
    mkdir -p "$DATA_DIR"
    OTLP_ENDPOINT="$OTLP_ENDPOINT" \
    EMIT_INTERVAL="$EMIT_INTERVAL" \
    NODE_NAME="du-sno-demo" \
    CLUSTER_NAME="demo-cluster" \
        expanso-edge run --local --data-dir "$DATA_DIR" \
            --config "${SCRIPT_DIR}/pipeline-otlp.yaml" \
            --api-listen localhost:9010 &
    EDGE_PID=$!
    echo $EDGE_PID > /tmp/expanso-edge.pid
    sleep 5

    # Deploy the pipeline job
    step "Deploying pipeline job..."
    EXPANSO_CLI_ENDPOINT=http://localhost:9010 \
        expanso-cli job deploy "${SCRIPT_DIR}/pipeline-otlp.yaml" --force

    success "Pipeline deployed and running!"
    echo ""
    echo -e "${BOLD}To view metrics, open a new terminal and run:${NC}"
    echo -e "  ${PURPLE}tail -f /tmp/oran-metrics.log${NC}"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    # Wait for edge to exit (it won't unless killed)
    wait $EDGE_PID
}

# Run with Grafana stack (requires Docker)
run_local_grafana() {
    check_prereqs

    if ! command -v docker &> /dev/null; then
        error "Docker not found. Install Docker to use the Grafana stack."
        exit 1
    fi

    step "Starting Grafana observability stack..."

    # Create docker-compose for the demo
    cat > /tmp/expanso-demo-compose.yaml << 'COMPOSE'
version: '3.8'
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4318:4318"
      - "8889:8889"

  prometheus:
    image: prom/prometheus:latest
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ./prometheus.yaml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_AUTH_ANONYMOUS_ENABLED=true
    ports:
      - "3000:3000"
    volumes:
      - ./grafana-datasources.yaml:/etc/grafana/provisioning/datasources/datasources.yaml
COMPOSE

    # Create OTel collector config
    cat > /tmp/otel-config.yaml << 'OTEL'
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"

service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
OTEL

    # Create Prometheus config
    cat > /tmp/prometheus.yaml << 'PROM'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
PROM

    # Create Grafana datasource
    cat > /tmp/grafana-datasources.yaml << 'GRAFANA'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
GRAFANA

    cd /tmp
    docker compose -f expanso-demo-compose.yaml up -d

    success "Grafana stack started!"
    echo ""
    echo -e "  ${BOLD}Access:${NC}"
    echo -e "    Grafana:    ${PURPLE}http://localhost:3000${NC} (admin/admin)"
    echo -e "    Prometheus: ${PURPLE}http://localhost:9090${NC}"
    echo ""

    # Wait for services
    sleep 5

    # Start edge agent with API enabled
    step "Starting Expanso Edge agent..."
    mkdir -p "$DATA_DIR"
    OTLP_ENDPOINT="http://localhost:4318" \
    EMIT_INTERVAL="$EMIT_INTERVAL" \
    NODE_NAME="du-sno-demo" \
    CLUSTER_NAME="demo-cluster" \
        expanso-edge run --local --data-dir "$DATA_DIR" \
            --config "${SCRIPT_DIR}/pipeline-otlp.yaml" \
            --api-listen localhost:9010 &
    EDGE_PID=$!
    echo $EDGE_PID > /tmp/expanso-edge.pid
    sleep 5

    # Deploy the pipeline job
    step "Deploying pipeline job..."
    EXPANSO_CLI_ENDPOINT=http://localhost:9010 \
        expanso-cli job deploy "${SCRIPT_DIR}/pipeline-otlp.yaml" --force

    success "Pipeline deployed and running!"
    echo ""
    echo -e "  ${BOLD}View dashboards at:${NC} ${PURPLE}http://localhost:3000${NC}"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    wait $EDGE_PID
}

# Deploy to OpenShift
deploy_openshift() {
    check_openshift_prereqs

    step "Deploying to OpenShift..."

    cd "${SCRIPT_DIR}"

    if command -v oc &> /dev/null; then
        oc apply -k deploy/openshift/
    else
        kubectl apply -k deploy/openshift/
    fi

    success "Deployed to OpenShift!"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo "    1. Configure OTLP endpoint:"
    echo "       oc set env deployment/expanso-oran-collector \\"
    echo "         OTLP_ENDPOINT=http://your-otlp-receiver:4318"
    echo ""
    echo "    2. Check pod status:"
    echo "       oc get pods -n expanso-system"
    echo ""
    echo "    3. View logs:"
    echo "       oc logs -f deployment/expanso-oran-collector -n expanso-system"
}

# Clean up
cleanup() {
    step "Cleaning up..."

    # Kill expanso-edge
    if [[ -f /tmp/expanso-edge.pid ]]; then
        kill "$(cat /tmp/expanso-edge.pid)" 2>/dev/null || true
        rm /tmp/expanso-edge.pid
        success "Stopped Expanso Edge agent"
    fi

    # Kill mock OTLP receiver
    if [[ -f /tmp/expanso-mock-otlp.pid ]]; then
        kill "$(cat /tmp/expanso-mock-otlp.pid)" 2>/dev/null || true
        rm /tmp/expanso-mock-otlp.pid
        success "Stopped mock OTLP receiver"
    fi

    # Clean up local data directory
    if [[ -d "$DATA_DIR" ]]; then
        rm -rf "$DATA_DIR"
        success "Cleaned up local data directory"
    fi

    # Stop Docker compose
    if [[ -f /tmp/expanso-demo-compose.yaml ]]; then
        cd /tmp
        docker compose -f expanso-demo-compose.yaml down 2>/dev/null || true
        rm -f /tmp/expanso-demo-compose.yaml /tmp/otel-config.yaml \
              /tmp/prometheus.yaml /tmp/grafana-datasources.yaml
        success "Stopped Grafana stack"
    fi

    # Delete OpenShift resources
    if command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
        if oc get namespace expanso-system &> /dev/null 2>&1; then
            read -p "Delete OpenShift resources? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                oc delete -k "${SCRIPT_DIR}/deploy/openshift/" 2>/dev/null || true
                success "Deleted OpenShift resources"
            fi
        fi
    fi

    success "Cleanup complete"
}

# Print usage
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  local          Run locally with mock OTLP receiver"
    echo "  local-grafana  Run locally with Grafana stack (requires Docker)"
    echo "  openshift      Deploy to OpenShift"
    echo "  clean          Clean up all resources"
    echo ""
    echo "Environment variables:"
    echo "  OTLP_ENDPOINT  OTLP HTTP endpoint (default: http://localhost:4318)"
    echo "  OTLP_PORT      Port for mock OTLP receiver (default: 4318)"
    echo "  EMIT_INTERVAL  Telemetry interval (default: 5s)"
}

# Main
main() {
    print_banner

    case "${1:-}" in
        local)
            run_local
            ;;
        local-grafana)
            run_local_grafana
            ;;
        openshift)
            deploy_openshift
            ;;
        clean)
            cleanup
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Handle Ctrl+C
trap cleanup EXIT

main "$@"
