#!/usr/bin/env bash
#
# Run generate_train_set.py (with the vision-validation feedback loop ON by
# default) inside a podman container that has Playwright + headless Chromium.
# Builds the image on first run. Mirrors run-vision-viewer.sh.
#
# The dataset dir (this directory) is bind-mounted at /work, so prompts.txt,
# train.jsonl, rejects.jsonl, and validated-html/ are shared live with the host.
#
# Env vars (all optional):
#   LLAMA_BASE_URL   llama.cpp OpenAI-compatible endpoint reachable from inside
#                    the container. Default: http://127.0.0.1:8080 (works with
#                    the runner's default --network=host; without it, 127.0.0.1
#                    is the container itself — use the host's LAN IP).
#   LLAMA_MODEL      model id passed via --model (default: local-model)
#   LLAMA_API_KEY    bearer token if the endpoint needs one
#   CONCURRENCY      --concurrency (default: 2; the vision loop is heavy)
#   MAX_TOKENS       --max-tokens generation cap (default: 4096)
#   MAX_REPLY_TOKENS --max-reply-tokens, binding cap on the SAVED reply (4096)
#   MAX_CONTEXT      --max-context, full-record cap (default: 4096)
#   VISION_VALIDATE  set to 0 to pass --no-vision-validate (default: 1 = on)
#   VALIDATE_MAX_DEPTH --vision-max-depth recursive fix rounds (default: 5)
#   VERBOSE          set to 1 to pass --verbose (default: 0)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="threejs-train-generator"
DOCKERFILE="${HERE}/Dockerfile.generator"
BASE_URL="${LLAMA_BASE_URL:-http://127.0.0.1:8080}"

if ! command -v podman >/dev/null 2>&1; then
  echo "podman not found. Install it first (e.g. apt install podman)." >&2
  exit 1
fi

# Build the image if it doesn't exist locally.
if ! podman image exists "$IMAGE"; then
  echo "Image '$IMAGE' not found — building from $DOCKERFILE …"
  podman build -t "$IMAGE" -f "$DOCKERFILE" "$HERE"
fi

# Optional flags assembled from env.
EXTRA=()
[[ "${VISION_VALIDATE:-1}" == "0" ]] && EXTRA+=(--no-vision-validate)
[[ "${VERBOSE:-0}" == "1" ]]         && EXTRA+=(--verbose)

# --network=host so 127.0.0.1:8080 on the host is reachable from the container.
# /work is mounted rw so the generator appends to train.jsonl / rejects.jsonl
# and writes validated-html/ back to the host. ':Z' relabels for SELinux hosts.
exec podman run --rm -it \
  --network=host \
  --userns=keep-id \
  -v "${HERE}:/work:Z" \
  -e LLAMA_API_KEY="${LLAMA_API_KEY:-${OPENAI_API_KEY:-}}" \
  -e LLAMA_TIMEOUT="${LLAMA_TIMEOUT:-600}" \
  -w /work \
  "$IMAGE" \
  python3 /app/generate_train_set.py \
    --prompts /work/prompts.txt \
    --out /work/train.jsonl \
    --rejects /work/rejects.jsonl \
    --base-url "${BASE_URL}" \
    --model "${LLAMA_MODEL:-local-model}" \
    --api-key "${LLAMA_API_KEY:-${OPENAI_API_KEY:-}}" \
    --concurrency "${CONCURRENCY:-2}" \
    --max-tokens "${MAX_TOKENS:-4096}" \
    --max-reply-tokens "${MAX_REPLY_TOKENS:-4096}" \
    --max-context "${MAX_CONTEXT:-4096}" \
    --vision-max-depth "${VALIDATE_MAX_DEPTH:-5}" \
    --timeout "${LLAMA_TIMEOUT:-600}" \
    --resume \
    "${EXTRA[@]}"
