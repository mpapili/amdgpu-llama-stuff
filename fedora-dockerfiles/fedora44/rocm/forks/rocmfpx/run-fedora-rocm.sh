#!/usr/bin/env bash
set -euo pipefail

# Rootless Podman can set unlimited memlock only when the host user's hard
# limit permits it. Try now and explain the permanent host fix if necessary.
if ! ulimit -l unlimited 2>/dev/null; then
    echo "WARNING: could not raise memlock limit (current: $(ulimit -l) KiB)."
    echo "For a permanent fix, create /etc/security/limits.d/99-memlock.conf with:"
    echo "  ${USER}  soft  memlock  unlimited"
    echo "  ${USER}  hard  memlock  unlimited"
    echo "then log out and back in."
fi

podman run --rm \
    --name llama-rocmfpx \
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
    -v /home/mike/Downloads/LLMs:/models:ro \
    -e HOME=/tmp \
    -e HSA_ENABLE_SDMA=0 \
    -p 0.0.0.0:8080:8080 \
    -it localhost/llama-cpp-rocmfpx-fedora-rocm \
    /bin/bash

# Example inside the container:
#   ./llama-server -m /models/model.gguf \
#       --ctx-size 160000 --gpu-layers 999 --flash-attn on \
#       --host 0.0.0.0 --no-mmap --threads 16 \
#       --cache-type-k q5_0 --cache-type-v q5_0 \
#       --batch-size 4096 --ubatch-size 128 --parallel 1
#
# For experimental dual-GPU use, add these environment options to podman run:
#   -e ROCR_VISIBLE_DEVICES=0,1 -e HIP_VISIBLE_DEVICES=0,1
# Then use --split-mode layer and an appropriate --tensor-split value.
