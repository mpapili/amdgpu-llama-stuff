#!/usr/bin/env bash
#
# Run the vision-validation viewer inside a podman container that has
# Playwright + headless Chromium set up. Builds the image on first run.
#
# The dataset dir (this directory) is bind-mounted at /work, so train.jsonl,
# labels.db, and the validated-html/ output are shared live with the host.
#
# Env vars (all optional):
#   LLAMA_BASE_URL  llama.cpp OpenAI-compatible endpoint reachable from
#                   inside the container. Default: http://192.168.1.1:8080
#                   (use the LAN IP — 127.0.0.1 inside the container is the
#                   container itself; pass --network=host below to use it).
#   LLAMA_MODEL     model id (default: local-model)
#   LLAMA_API_KEY   bearer token if the endpoint needs one
#   PORT            host port to forward (default: 8000)
#   NETWORK_HOST    set to 1 to use --network=host (lets 127.0.0.1:8080 work)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="threejs-vision-viewer"
DOCKERFILE="${HERE}/Dockerfile.vision-viewer"
PORT="${PORT:-8000}"

if ! command -v podman >/dev/null 2>&1; then
  echo "podman not found. Install it first (e.g. apt install podman)." >&2
  exit 1
fi

# Build the image if it doesn't exist locally.
if ! podman image exists "$IMAGE"; then
  echo "Image '$IMAGE' not found — building from $DOCKERFILE …"
  podman build -t "$IMAGE" -f "$DOCKERFILE" "$HERE"
fi

NET_ARGS=(--network=host)
if [[ "${NETWORK_HOST:-1}" != "1" ]]; then
  NET_ARGS=(-p "${PORT}:8000")
fi

# Mount this dir at /work (rw) so the viewer reads train.jsonl / labels.db and
# writes validated-html/ back to the host. ':Z' relabels for SELinux hosts
# (harmless elsewhere).
exec podman run --rm -it \
  "${NET_ARGS[@]}" \
  -v "${HERE}:/work:Z" \
  -e LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://192.168.1.1:8080}" \
  -e LLAMA_MODEL="${LLAMA_MODEL:-local-model}" \
  -e LLAMA_API_KEY="${LLAMA_API_KEY:-${OPENAI_API_KEY:-}}" \
  -e LLAMA_TIMEOUT="${LLAMA_TIMEOUT:-600}" \
  -e LLAMA_MAX_TOKENS="${LLAMA_MAX_TOKENS:-8192}" \
  -e VALIDATE_MAX_DEPTH="${VALIDATE_MAX_DEPTH:-5}" \
  -w /work \
  "$IMAGE"
