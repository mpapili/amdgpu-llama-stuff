#!/usr/bin/env python3
"""
llama-server-api.py - HTTP API wrapper for llama-server process management

Provides REST endpoints to:
- Start/stop/restart the llama-server
- Check server status
- Health checks

Environment variables:
  STARTUP_SCRIPT: Path to startup script (default: ./qwen3.5-27b-q4.sh)
  API_PORT: Port for API server (default: 9090)
  LOG_FILE: Log file path (default: /tmp/llama-server-api.log)
"""

import os
import subprocess
import signal
import time
import logging
import json
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional
from flask import Flask, jsonify, request

# Configuration
STARTUP_SCRIPT = os.getenv("STARTUP_SCRIPT", "./qwen3.5-27b-q4.sh")
API_PORT = int(os.getenv("API_PORT", "9090"))
LOG_FILE = os.getenv("LOG_FILE", "/tmp/llama-server-api.log")
RESTART_DELAY = 1
STARTUP_TIMEOUT = 30  # seconds to wait for server to be ready

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

# Global state
server_process: Optional[subprocess.Popen] = None
is_shutting_down = False

app = Flask(__name__)


def start_server() -> bool:
    """Start the llama-server process. Returns True if successful."""
    global server_process

    if server_process and server_process.poll() is None:
        logger.warning("Server already running (PID: %d)", server_process.pid)
        return False

    try:
        logger.info("Starting llama-server from: %s", STARTUP_SCRIPT)

        # Verify startup script exists
        if not Path(STARTUP_SCRIPT).exists():
            logger.error("Startup script not found: %s", STARTUP_SCRIPT)
            return False

        # Start the process in its own process group so we can kill the
        # entire group (bash + llama-server child) on stop.
        server_process = subprocess.Popen(
            ["bash", STARTUP_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            preexec_fn=os.setsid,
        )

        logger.info("Server started with PID: %d", server_process.pid)

        # Give it a moment to start
        time.sleep(1)

        # Check if it's still running
        if server_process.poll() is not None:
            stdout, stderr = server_process.communicate()
            logger.error(
                "Server process exited immediately. stdout: %s, stderr: %s",
                stdout,
                stderr,
            )
            return False

        return True

    except Exception as e:
        logger.error("Failed to start server: %s", str(e))
        return False


def stop_server() -> bool:
    """Stop the llama-server process. Returns True if successful."""
    global server_process

    if not server_process or server_process.poll() is not None:
        logger.info("Server not running")
        return False

    try:
        pgid = os.getpgid(server_process.pid)
        logger.info("Stopping server process group (PID: %d, PGID: %d)", server_process.pid, pgid)
        os.killpg(pgid, signal.SIGTERM)

        # Wait for bash wrapper to exit
        try:
            server_process.wait(timeout=5)
            logger.info("Bash wrapper stopped gracefully")
        except subprocess.TimeoutExpired:
            logger.warning(
                "Server did not stop gracefully, killing process group (PGID: %d)", pgid
            )
            os.killpg(pgid, signal.SIGKILL)
            server_process.wait()
            logger.info("Server killed")

        # Wait for the entire process group (including llama-server child) to die.
        # llama-server can take several seconds to unload GPU memory after bash exits.
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                os.killpg(pgid, 0)  # signal 0 = existence check
                time.sleep(0.5)
            except (ProcessLookupError, OSError):
                logger.info("Process group %d fully exited", pgid)
                break
        else:
            logger.warning("Process group %d still alive after 30s, sending SIGKILL", pgid)
            try:
                os.killpg(pgid, signal.SIGKILL)
            except (ProcessLookupError, OSError):
                pass

        return True

    except Exception as e:
        logger.error("Failed to stop server: %s", str(e))
        return False


def restart_server() -> bool:
    """Restart the server with a 1-second pause. Returns True if successful."""
    logger.info("Restart requested")

    # Stop
    if not stop_server():
        logger.warning("Stop failed or server was not running")

    # Pause
    logger.info("Pausing %d second(s)...", RESTART_DELAY)
    time.sleep(RESTART_DELAY)

    # Start
    return start_server()


def get_server_status() -> Dict:
    """Get current server status."""
    global server_process

    if server_process is None:
        return {
            "running": False,
            "pid": None,
            "status": "never_started",
        }

    poll_result = server_process.poll()

    if poll_result is None:
        return {
            "running": True,
            "pid": server_process.pid,
            "status": "running",
        }
    else:
        return {
            "running": False,
            "pid": server_process.pid,
            "exit_code": poll_result,
            "status": "stopped",
        }


# Routes


@app.route("/health", methods=["GET"])
def health() -> tuple:
    """Health check endpoint. Always returns 200 if API is alive."""
    return jsonify({"status": "ok", "timestamp": datetime.now().isoformat()}), 200


@app.route("/status", methods=["GET"])
def status() -> tuple:
    """Get server status."""
    try:
        status_info = get_server_status()
        status_info["timestamp"] = datetime.now().isoformat()
        return jsonify(status_info), 200
    except Exception as e:
        logger.error("Error getting status: %s", str(e))
        return jsonify({"error": str(e), "timestamp": datetime.now().isoformat()}), 500


@app.route("/start", methods=["POST"])
def start() -> tuple:
    """Start the server."""
    try:
        logger.info("Start request received")
        success = start_server()
        status_info = get_server_status()
        status_info["timestamp"] = datetime.now().isoformat()

        if success:
            return jsonify({"message": "Server started", **status_info}), 200
        else:
            return (
                jsonify(
                    {"error": "Failed to start server", **status_info,
                     "timestamp": datetime.now().isoformat()}
                ),
                500,
            )
    except Exception as e:
        logger.error("Error in /start: %s", str(e))
        return jsonify({"error": str(e), "timestamp": datetime.now().isoformat()}), 500


@app.route("/stop", methods=["POST"])
def stop() -> tuple:
    """Stop the server gracefully."""
    try:
        logger.info("Stop request received")
        success = stop_server()
        status_info = get_server_status()
        status_info["timestamp"] = datetime.now().isoformat()

        if success:
            return jsonify({"message": "Server stopped", **status_info}), 200
        else:
            return (
                jsonify(
                    {"error": "Failed to stop server", **status_info,
                     "timestamp": datetime.now().isoformat()}
                ),
                500,
            )
    except Exception as e:
        logger.error("Error in /stop: %s", str(e))
        return jsonify({"error": str(e), "timestamp": datetime.now().isoformat()}), 500


@app.route("/bounce", methods=["POST"])
def bounce() -> tuple:
    """Force stop, wait 1 second, and restart the server."""
    try:
        logger.info("Bounce request received")
        success = restart_server()
        status_info = get_server_status()
        status_info["timestamp"] = datetime.now().isoformat()

        if success:
            return jsonify({"message": "Server bounced (stopped, paused, restarted)", **status_info}), 200
        else:
            return (
                jsonify(
                    {"error": "Bounce failed", **status_info,
                     "timestamp": datetime.now().isoformat()}
                ),
                500,
            )
    except Exception as e:
        logger.error("Error in /bounce: %s", str(e))
        return jsonify({"error": str(e), "timestamp": datetime.now().isoformat()}), 500


@app.route("/restart", methods=["POST"])
def restart() -> tuple:
    """Alias for /bounce endpoint."""
    return bounce()


def shutdown_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global is_shutting_down
    if is_shutting_down:
        return
    is_shutting_down = True

    logger.info("Shutdown signal received (%d), cleaning up...", signum)
    stop_server()
    logger.info("API server shutting down")
    os._exit(0)


if __name__ == "__main__":
    logger.info("=" * 60)
    logger.info("llama-server API starting")
    logger.info("Startup script: %s", STARTUP_SCRIPT)
    logger.info("API port: %d", API_PORT)
    logger.info("=" * 60)

    # Setup signal handlers
    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)

    # Start initial server
    if not start_server():
        logger.error("Failed to start server during initialization")
        exit(1)

    # Start API server
    try:
        app.run(host="0.0.0.0", port=API_PORT, debug=False, use_reloader=False)
    except Exception as e:
        logger.error("API server error: %s", str(e))
        stop_server()
        exit(1)
