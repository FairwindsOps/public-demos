# GPU Metrics & Dashboard

Adds NVIDIA GPU utilization metrics + a Grafana dashboard alongside the Ollama
deployment.

## Components

- **`dcgm-exporter.values.yaml`** – Helm values for `nvidia/dcgm-exporter`.
  Runs as a DaemonSet on GPU nodes, exposes Prometheus metrics on `:9400`,
  and creates a `ServiceMonitor` for kube-prometheus-stack to scrape.
- **`nvidia-dcgm-dashboard-configmap.yaml`** – Grafana dashboard packaged as a
  ConfigMap with the `grafana_dashboard: "1"` label so the
  kube-prometheus-stack Grafana sidecar auto-imports it. Panels cover:
  - GPU utilization %
  - Framebuffer (VRAM) usage
  - Temperature & power draw
  - SM / tensor / encoder activity
  - SM clock and PCIe throughput
- **`install-dcgm-exporter.sh`** – installs both.

## Prerequisites

1. NVIDIA driver + container toolkit on GPU nodes (or the NVIDIA GPU Operator).
2. `kube-prometheus-stack` installed in the cluster.
3. Your Prometheus CR's `serviceMonitorSelector` matches the `release` label
   set in `dcgm-exporter.values.yaml` (default: `kube-prometheus-stack`).
   Verify with:
   ```sh
   kubectl get prometheus -A -o jsonpath='{.items[*].spec.serviceMonitorSelector}'
   ```
   Adjust `serviceMonitor.additionalLabels.release` if it doesn't match.

## Install

```sh
cd dcgm-exporter
# Override GRAFANA_NS if your Grafana sidecar lives somewhere other than `monitoring`
GRAFANA_NS=monitoring ./install-dcgm-exporter.sh
```

## Verify

```sh
# DaemonSet up on every GPU node
kubectl -n gpu-monitoring get pods -l app.kubernetes.io/name=dcgm-exporter -o wide

# Metrics flowing
kubectl -n gpu-monitoring port-forward svc/dcgm-exporter 9400:9400
curl -s localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL

# Prometheus is scraping
# (in Prometheus UI) Status → Targets → search for "dcgm-exporter"

# Dashboard imported
# (in Grafana) Dashboards → search "NVIDIA DCGM Exporter"
```
