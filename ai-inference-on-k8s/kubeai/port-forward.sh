#!/bin/bash

# Port Forward Manager Script
# Creates and maintains kubectl port-forward connections
# Auto-restarts if connections drop
set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-kai}"
LOG_DIR="${LOG_DIR:-./logs}"

# Define your port forwards here
# Format: "LOCAL_PORT:NAMESPACE:SERVICE_NAME:POD_PORT"
declare -a PORT_FORWARDS=(
    "11436:kai:kubeai:80"           # Kubeai inference
    "8080:kai:open-webui:80"      # Open WebUI
    "8081:kai:grafana:3000"       # Grafana
    "9090:kai:prometheus:9090"      # Prometheus
    "11435:ollama:ollama:11434"     # Ollama
)

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Create log directory
mkdir -p "$LOG_DIR"

# Cleanup function for ctrl-c
cleanup() {
    log "Stopping all port forwards..."
    # Kill keep-alive processes (their own PIDs)
    for pidfile in "${LOG_DIR}"/keepalive-*.pid; do
        if [[ -f "$pidfile" ]]; then
            pid=$(cat "$pidfile" 2>/dev/null) && kill "$pid" 2>/dev/null || true
        fi
    done
    # Kill kubectl port-forward processes
    pkill -9 -f "kubectl port-forward" 2>/dev/null || true
    rm -f "${LOG_DIR}"/port-*.pid "${LOG_DIR}"/keepalive-*.pid
    log "Done"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Keep port-forward alive with auto-restart
keep_alive() {
    local local_port="$1"
    local namespace="$2"
    local service="$3"
    local remote_port="$4"

    local pid_file="${LOG_DIR}/port-${local_port}.pid"
    local log_file="${LOG_DIR}/port-${local_port}.log"

    while true; do
        # Check if port-forward is running
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                sleep 5
                continue
            fi
        fi

        # Port-forward not running, start it
        rm -f "$pid_file"

        log "Starting: localhost:${local_port} -> ${namespace}/svc/${service}:${remote_port}"

        # Start kubectl in background, redirect both stdout and stderr to log
        kubectl port-forward --address 0.0.0.0 -n "$namespace" "svc/${service}" "${local_port}:${remote_port}" >> "$log_file" 2>&1 &
        local k8s_pid=$!
        echo $k8s_pid > "$pid_file"

        # Check if it died immediately
        sleep 2
        if ! kill -0 "$k8s_pid" 2>/dev/null; then
            log "FAILED - check ${log_file} for errors"
            last_line=$(tail -3 "$log_file" 2>/dev/null)
            [[ -n "$last_line" ]] && log "Error: $last_line"
        fi
    done
}

# Start all port forwards
start_all() {
    rm -f "${LOG_DIR}"/port-*.pid "${LOG_DIR}"/keepalive-*.pid

    log "Starting port forwards..."

    for pf in "${PORT_FORWARDS[@]}"; do
        IFS=':' read -r local_port namespace service remote_port <<< "$pf"
        keep_alive "$local_port" "$namespace" "$service" "$remote_port" &
        echo $! > "${LOG_DIR}/keepalive-${local_port}.pid"
    done

    log "All port forwards started (Ctrl-C to stop)"
    wait
}

# Stop all port forwards
stop_all() {
    log "Stopping port forwards..."
    # Kill keep-alive processes
    for pidfile in "${LOG_DIR}"/keepalive-*.pid; do
        if [[ -f "$pidfile" ]]; then
            pid=$(cat "$pidfile" 2>/dev/null) && kill -9 "$pid" 2>/dev/null || true
        fi
    done
    # Kill kubectl port-forward processes
    pkill -9 -f "kubectl port-forward" 2>/dev/null || true
    sleep 1
    rm -f "${LOG_DIR}"/port-*.pid "${LOG_DIR}"/keepalive-*.pid
    log "Done"
}

# Status
status() {
    for pf in "${PORT_FORWARDS[@]}"; do
        IFS=':' read -r local_port namespace service remote_port <<< "$pf"
        printf "%s -> %s/%s:%s - " "$local_port" "$namespace" "$service" "$remote_port"
        if [[ -f "${LOG_DIR}/port-${local_port}.pid" ]]; then
            if kill -0 "$(cat "${LOG_DIR}/port-${local_port}.pid")" 2>/dev/null; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
        else
            echo "NOT RUNNING"
        fi
    done
}

case "${1:-}" in
    start) start_all ;;
    stop) stop_all ;;
    status) status ;;
    restart)
        stop_all
        sleep 1
        start_all
        ;;
    *) echo "Usage: $0 {start|stop|status|restart}" ;;
esac
