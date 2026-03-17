#!/usr/bin/env bash
set -euo pipefail

# llama-server-control-api.sh - Control interface for llama-server-api HTTP wrapper
# Usage:
#   ./llama-server-control-api.sh status [HOST:PORT]
#   ./llama-server-control-api.sh start [HOST:PORT]
#   ./llama-server-control-api.sh stop [HOST:PORT]
#   ./llama-server-control-api.sh bounce [HOST:PORT]
#   ./llama-server-control-api.sh restart [HOST:PORT]

COMMAND="${1:-status}"
API_ENDPOINT="${2:-localhost:9090}"

# Ensure curl is available
if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is required but not installed"
    exit 1
fi

case "$COMMAND" in
    status)
        echo "Querying API status at $API_ENDPOINT..."
        curl -s "http://$API_ENDPOINT/status" | jq . || echo "Failed to get status"
        ;;
    start)
        echo "Sending START request to $API_ENDPOINT..."
        curl -s -X POST "http://$API_ENDPOINT/start" | jq .
        ;;
    stop)
        echo "Sending STOP request to $API_ENDPOINT..."
        curl -s -X POST "http://$API_ENDPOINT/stop" | jq .
        ;;
    bounce|restart)
        echo "Sending BOUNCE request to $API_ENDPOINT..."
        echo "(Server will stop, pause 1s, and restart)"
        curl -s -X POST "http://$API_ENDPOINT/bounce" | jq .
        ;;
    health)
        echo "Checking API health at $API_ENDPOINT..."
        curl -s "http://$API_ENDPOINT/health" | jq .
        ;;
    *)
        echo "Usage: $0 <command> [HOST:PORT]"
        echo ""
        echo "Commands:"
        echo "  status [HOST:PORT]   - Get server and API status"
        echo "  start [HOST:PORT]    - Start the server"
        echo "  stop [HOST:PORT]     - Stop the server gracefully"
        echo "  bounce [HOST:PORT]   - Force stop, wait 1s, restart"
        echo "  restart [HOST:PORT]  - Alias for bounce"
        echo "  health [HOST:PORT]   - Check if API is alive"
        echo ""
        echo "HOST:PORT defaults to: localhost:9090"
        echo ""
        echo "Examples:"
        echo "  ./llama-server-control-api.sh status"
        echo "  ./llama-server-control-api.sh bounce localhost:9090"
        echo "  ./llama-server-control-api.sh status 192.168.1.100:9090"
        exit 1
        ;;
esac
