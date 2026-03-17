#!/usr/bin/env bash
set -euo pipefail

# llama-server-wrapper.sh - Process manager for llama-server with restart capability
# Usage: llama-server-wrapper.sh <path-to-llama-startup-script> [args...]
# Control via: kill -USR1 $PID to restart, kill -TERM $PID to gracefully shutdown

STARTUP_SCRIPT="$1"
shift || true
STARTUP_ARGS=("$@")

PID_FILE="${PID_FILE:-./.llama-server-wrapper.pid}"
LOG_FILE="${LOG_FILE:-./.llama-server.log}"
RESTART_DELAY=1

# Cleanup on exit
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wrapper shutting down..." | tee -a "$LOG_FILE"
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    exit 0
}

# Handle restart signal (USR1)
handle_restart() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RESTART requested - stopping server..." | tee -a "$LOG_FILE"
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pausing ${RESTART_DELAY}s..." | tee -a "$LOG_FILE"
    sleep "$RESTART_DELAY"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting server..." | tee -a "$LOG_FILE"
    start_server
}

# Start the server
start_server() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting llama-server from: $STARTUP_SCRIPT" | tee -a "$LOG_FILE"
    bash "$STARTUP_SCRIPT" "${STARTUP_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server started with PID: $SERVER_PID" | tee -a "$LOG_FILE"
}

# Trap signals
trap cleanup SIGTERM SIGINT
trap handle_restart SIGUSR1

# Write wrapper PID
echo $$ > "$PID_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wrapper started with PID: $$, listening for signals..." | tee -a "$LOG_FILE"

# Start server initially
start_server

# Keep wrapper alive, monitor server process
while true; do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server process died unexpectedly (PID: $SERVER_PID), restarting..." | tee -a "$LOG_FILE"
        sleep "$RESTART_DELAY"
        start_server
    fi
    sleep 1
done
