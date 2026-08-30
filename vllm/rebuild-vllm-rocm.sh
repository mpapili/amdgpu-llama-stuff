#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE_NAME=${VLLM_ROCM_IMAGE:-localhost/vllm-rocm:latest}

command -v podman >/dev/null 2>&1 || {
    printf 'Error: podman is not installed or not on PATH.\n' >&2
    exit 1
}

printf 'Building %s from %s...\n' "$IMAGE_NAME" "$SCRIPT_DIR/Containerfile.vllm-rocm"
podman build \
    --pull=always \
    --tag "$IMAGE_NAME" \
    --file "$SCRIPT_DIR/Containerfile.vllm-rocm" \
    "$SCRIPT_DIR"

printf 'Built %s successfully.\n' "$IMAGE_NAME"
