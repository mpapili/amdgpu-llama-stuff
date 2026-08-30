#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME=${VLLM_ROCM_IMAGE:-localhost/vllm-rocm:latest}
CONTAINER_NAME=${VLLM_ROCM_CONTAINER:-vllm-rocm}
HOST_PORT=${VLLM_ROCM_PORT:-8081}
MODEL_DIR=${VLLM_ROCM_MODEL_DIR:-"$HOME/Downloads/LLMs"}

command -v podman >/dev/null 2>&1 || {
    printf 'Error: podman is not installed or not on PATH.\n' >&2
    exit 1
}

[[ -d "$MODEL_DIR" ]] || {
    printf 'Error: model directory does not exist: %s\n' "$MODEL_DIR" >&2
    exit 1
}

if podman container exists "$CONTAINER_NAME"; then
    printf 'Removing existing container %s...\n' "$CONTAINER_NAME"
    podman rm --force "$CONTAINER_NAME" >/dev/null
fi

printf 'Starting vLLM ROCm container with a Bash shell.\n'
printf 'Models: %s -> /models\n' "$MODEL_DIR"
printf 'Published port: http://0.0.0.0:%s\n' "$HOST_PORT"

exec podman run \
    --name "$CONTAINER_NAME" \
    --replace \
    --rm \
    --device=/dev/kfd \
    --device=/dev/dri \
    --cap-drop=ALL \
    --group-add keep-groups \
    --user "$(id -u):$(id -g)" \
    --ipc=host \
    --ulimit memlock=-1:-1 \
    --ulimit stack=67108864 \
    --security-opt no-new-privileges \
    --security-opt label=disable \
    --security-opt seccomp=unconfined \
    --volume "${MODEL_DIR}:/models:ro,Z" \
    --env HOME=/tmp \
    --env HSA_ENABLE_SDMA=0 \
    --publish "0.0.0.0:${HOST_PORT}:8081" \
    --interactive \
    --tty \
    --entrypoint /bin/bash \
    "$IMAGE_NAME"
