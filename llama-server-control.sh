#!/usr/bin/env bash
set -euo pipefail

# llama-server-control.sh - Control interface for llama-server-wrapper
# Usage:
#   ./llama-server-control.sh restart [PID_FILE]
#   ./llama-server-control.sh shutdown [PID_FILE]
#   ./llama-server-control.sh status [PID_FILE]

COMMAND="${1:-status}"
PID_FILE="${2:-./.llama-server-wrapper.pid}"

get_wrapper_pid() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "ERROR: PID file not found: $PID_FILE"
        echo "Is the wrapper running? Start it with: llama-server-wrapper.sh <startup-script>"
        return 1
    fi
    cat "$PID_FILE"
}

case "$COMMAND" in
    restart)
        PID=$(get_wrapper_pid) || exit 1
        if kill -0 "$PID" 2>/dev/null; then
            echo "Sending RESTART signal to wrapper (PID: $PID)..."
            kill -USR1 "$PID"
            echo "Restart signal sent. Server will stop, pause 1s, and restart."
        else
            echo "ERROR: Wrapper process not found (PID: $PID)"
            exit 1
        fi
        ;;
    shutdown)
        PID=$(get_wrapper_pid) || exit 1
        if kill -0 "$PID" 2>/dev/null; then
            echo "Sending SHUTDOWN signal to wrapper (PID: $PID)..."
            kill -TERM "$PID"
            echo "Shutdown signal sent. Waiting for graceful shutdown..."
            wait "$PID" 2>/dev/null || true
            echo "Wrapper and server stopped."
        else
            echo "ERROR: Wrapper process not found (PID: $PID)"
            exit 1
        fi
        ;;
    status)
        if [[ ! -f "$PID_FILE" ]]; then
            echo "Status: NOT RUNNING (no PID file found)"
            exit 1
        fi
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "Status: RUNNING"
            echo "Wrapper PID: $PID"
            ps -p "$PID" -o pid,ppid,cmd,lstart --no-headers || true
        else
            echo "Status: STOPPED (PID file exists but process not found)"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 <command> [PID_FILE]"
        echo ""
        echo "Commands:"
        echo "  restart [PID_FILE]   - Force stop, wait 1s, restart the server"
        echo "  shutdown [PID_FILE]  - Gracefully shutdown the server and wrapper"
        echo "  status [PID_FILE]    - Check if wrapper is running (default if no command)"
        echo ""
        echo "PID_FILE defaults to: ./.llama-server-wrapper.pid"
        exit 1
        ;;
esac
