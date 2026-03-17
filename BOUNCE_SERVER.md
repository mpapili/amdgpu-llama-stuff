# Server Bounce Control

This system provides an HTTP API wrapper around `llama-server` that allows remote control for restarts, shutdowns, and status checks.

## Architecture

The wrapper exposes a simple REST API on a dedicated port (default: **9090**) that can trigger:
- **Bounce/Restart** - Force stop, wait 1 second, restart
- **Start/Stop** - Control server lifecycle
- **Status** - Check server state
- **Health** - Verify API is responding

## Quick Start

### Docker Run

Everything is built into the image, just expose ports 8080 (llama-server) and 9090 (API):

```bash
docker run --rm \
    --name llama-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    -v /path/to/models:/models:Z \
    -p 0.0.0.0:8080:8080 \
    -p 0.0.0.0:9090:9090 \
    fedora-llama-cpp:latest \
    /bin/bash
```

Use the provided script (pre-configured):
```bash
./fedora-run-docker.sh
```

Inside the container, start the API:
```bash
# List available qwen runners
ls qwen*.sh

# Start API with a specific runner
python3 mike-utils/llama-server-api.py

# Or set a custom startup script
STARTUP_SCRIPT=./qwen3.5-27b-q4.sh python3 mike-utils/llama-server-api.py
```

### Local Usage (No Docker)

```bash
# Install dependencies
pip3 install flask

# Start API wrapper
STARTUP_SCRIPT=./qwen3.5-27b-q4.sh python3 mike-utils/llama-server-api.py
```

## API Endpoints

All endpoints respond with JSON. The API runs on **port 9090** by default.

### Status & Health

**GET /health**
- Check if API is alive (always returns 200)
- Response: `{"status": "ok", "timestamp": "..."}`

**GET /status**
- Get server status (running, stopped, never started)
- Response: `{"running": true/false, "pid": <pid>, "status": "...", "timestamp": "..."}`

### Server Control

**POST /start**
- Start the server
- Response: `{"message": "Server started", "running": true, "pid": <pid>, ...}`

**POST /stop**
- Gracefully stop the server (waits up to 5 seconds)
- Response: `{"message": "Server stopped", "running": false, ...}`

**POST /bounce** (or **/restart**)
- Force stop → wait 1 second → restart
- Response: `{"message": "Server bounced (stopped, paused, restarted)", "running": true, "pid": <pid>, ...}`

## Usage Examples

### Using curl

```bash
# Check status
curl http://localhost:9090/status | jq

# Bounce (restart with 1s pause)
curl -X POST http://localhost:9090/bounce | jq

# Stop server
curl -X POST http://localhost:9090/stop | jq

# Start server
curl -X POST http://localhost:9090/start | jq
```

### Using the control script

The included `llama-server-control-api.sh` simplifies API calls:

```bash
# Check status
./llama-server-control-api.sh status

# Bounce the server
./llama-server-control-api.sh bounce

# Stop server
./llama-server-control-api.sh stop

# Remote API (specify host:port)
./llama-server-control-api.sh bounce 192.168.1.100:9090
./llama-server-control-api.sh status my-server.example.com:9090
```

### From Another Container

```bash
# Inside the container or from your host
curl -X POST http://llama-rocm:9090/bounce
```

## Environment Variables

Configure the API wrapper via environment variables:

```bash
STARTUP_SCRIPT=./qwen3.5-27b-q4.sh \
API_PORT=9090 \
LOG_FILE=./llama-server-api.log \
python3 mike-utils/llama-server-api.py
```

| Variable | Default | Description |
|----------|---------|-------------|
| `STARTUP_SCRIPT` | `./qwen3.5-27b-q4.sh` | Path to your model startup script |
| `API_PORT` | `9090` | Port the API listens on |
| `LOG_FILE` | `./llama-server-api.log` | Log file location |

## Monitoring

### View Logs

```bash
# Inside container
tail -f llama-server-api.log

# Or from host (if logs are mounted)
docker exec llama-rocm tail -f llama-server-api.log
```

### Log Format

```
[2026-03-16 10:15:42] INFO - Starting llama-server from: ./qwen3.5-27b-q4.sh
[2026-03-16 10:15:43] INFO - Server started with PID: 12345
[2026-03-16 10:16:00] INFO - Bounce request received
[2026-03-16 10:16:00] INFO - Stopping server (PID: 12345)
[2026-03-16 10:16:01] INFO - Pausing 1 second(s)...
[2026-03-16 10:16:02] INFO - Starting llama-server from: ./qwen3.5-27b-q4.sh
[2026-03-16 10:16:03] INFO - Server started with PID: 12346
```

## Architecture Details

### Components

**llama-server-api.py** (Python/Flask)
- HTTP server that manages llama-server lifecycle
- Starts server in background subprocess
- Handles requests to start/stop/bounce
- Monitors process and logs all activity
- Gracefully handles shutdown signals (SIGTERM, SIGINT)

**llama-server-control-api.sh** (Bash client)
- CLI wrapper around the HTTP API
- Simplifies curl commands with user-friendly commands
- Supports remote endpoints (host:port)
- Pretty-prints JSON responses (with jq)

### Process Flow: Bounce Request

```
User POST /bounce
    ↓
API receives request
    ↓
Terminate llama-server process
    ↓
Wait for graceful shutdown (5s timeout, then kill)
    ↓
Sleep 1 second
    ↓
Start new llama-server process
    ↓
Return status response
    ↓
User gets {"message": "Server bounced...", "running": true, ...}
```

## Troubleshooting

**API not responding**
- Check: `curl http://localhost:9090/health`
- Verify port 9090 is exposed: `-p 0.0.0.0:9090:9090` in docker run
- Check container logs: `docker logs llama-rocm`

**Bounce fails**
- Server may have crashed before; check logs: `tail -f llama-server-api.log`
- Ensure `STARTUP_SCRIPT` path is correct
- Verify the startup script runs independently: `bash ./qwen3.5-27b-q4.sh`

**Server won't start after bounce**
- Check logs for startup errors
- Verify model files exist at expected paths
- Ensure GPU devices are properly mounted

**Control script can't find jq**
- jq is used for JSON formatting (optional)
- Install: `sudo dnf install jq` (Fedora) or `apt-get install jq` (Ubuntu)
- Or remove `| jq .` from commands for raw JSON

## Integration Examples

### Monitoring Script

```bash
#!/bin/bash
# Poll server status every 30 seconds
while true; do
    STATUS=$(curl -s http://localhost:9090/status)
    echo "[$(date)] $STATUS"
    sleep 30
done
```

### Auto-Restart on Crash

The API already auto-restarts the server if the process dies unexpectedly. No additional setup needed.

### Kubernetes Probe

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 9090
  initialDelaySeconds: 30
  periodSeconds: 10
```

## Differences from Signal-Based Wrapper

Old approach (llama-server-wrapper.sh):
- Signal-based control (SIGUSR1, SIGTERM)
- Required knowing the wrapper PID
- Limited to local machine

**New HTTP API approach:**
- ✅ Remote control over network
- ✅ Standard HTTP/REST interface
- ✅ Easy integration with monitoring/orchestration tools
- ✅ JSON responses for structured data
- ✅ Better logging and observability
