#!/usr/bin/env bash
set -euo pipefail

IMAGE="localhost/pytorch-rocm-finetune"
HOST_MODEL_DIR="/home/mike/Downloads/LLMs/gemma4-12b-raw"
HOST_WORKDIR="$(pwd)"   # your training scripts / data live here

# Sanity check the model exists before we bother launching
if [[ ! -f "${HOST_MODEL_DIR}/model.safetensors" ]]; then
  echo "ERROR: model.safetensors not found in ${HOST_MODEL_DIR}" >&2
  exit 1
fi

# Note - the env variables force us to only use the w6800
podman run --rm -it \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add keep-groups \
  --security-opt seccomp=unconfined \
  --ipc=host \
  `# --shm-size=8g   # <-- use THIS instead of --ipc=host if you want isolation` \
  -e HIP_VISIBLE_DEVICES=1 \
  -e HSA_OVERRIDE_GFX_VERSION=10.3.0 \
  -e PYTORCH_HIP_ALLOC_CONF=expandable_segments:True \
  -v "${HOST_MODEL_DIR}:/models/gemma4-12b:ro,Z" \
  -v "${HOST_WORKDIR}:/workspace:Z" \
  -w /workspace \
  "${IMAGE}" \
  "$@"
