#!/bin/bash
set -euo pipefail

# Install the NVIDIA DCGM Exporter so Prometheus can scrape GPU metrics
# (DCGM_FI_DEV_GPU_UTIL, DCGM_FI_DEV_FB_USED, DCGM_FI_DEV_GPU_TEMP, ...).
#
# Requires:
#   - NVIDIA driver + container toolkit on GPU nodes (or NVIDIA GPU Operator)
#   - kube-prometheus-stack (for ServiceMonitor + Grafana sidecar dashboards)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts >/dev/null 2>&1 || true
helm repo update gpu-helm-charts

helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace kai --create-namespace \
  --values "${SCRIPT_DIR}/dcgm-exporter.values.yaml"

# Install the standard NVIDIA DCGM Grafana dashboard (sidecar will auto-import).
# Adjust GRAFANA_NS to the namespace where Grafana's dashboard sidecar is watching
# (typically the kube-prometheus-stack namespace, e.g. "monitoring").
kubectl apply -f "${SCRIPT_DIR}/nvidia-dcgm-dashboard-configmap.yaml"
