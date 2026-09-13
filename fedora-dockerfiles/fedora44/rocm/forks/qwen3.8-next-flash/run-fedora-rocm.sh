#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# memlock: "sudo ulimit" does not exist — ulimit is a shell builtin.
# For rootless podman, --ulimit memlock=-1:-1 can only work if the
# *host user's* hard limit allows it. Try to raise it here; if that
# fails, tell the user how to fix it permanently.
# ──────────────────────────────────────────────
if ! ulimit -l unlimited 2>/dev/null; then
    echo "WARNING: could not raise memlock limit (current: $(ulimit -l) KiB)."
    echo "For a permanent fix, create /etc/security/limits.d/99-memlock.conf with:"
    echo "  ${USER}  soft  memlock  unlimited"
    echo "  ${USER}  hard  memlock  unlimited"
    echo "then log out and back in."
fi

# ──────────────────────────────────────────────
# Container runtime flags - --tensor-split 100,0 bug
# and multi-GPU pitfalls. Same notes as the upstream
# trio, applied to the unslothai qwen4exp fork image.
# ──────────────────────────────────────────────
# Critical: ROCm always requires disabling host-visible VRAM.
podman run --rm \
    --name llama-rocm-qwen4exp \
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
    -e GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1 \
    -p 0.0.0.0:8080:8080 \
    -it localhost/llama-cpp-qwen4exp-fedora-rocm \
    /bin/bash

# ─── How to run inside container (pick ONE) ───
#
# VERIFY BOTH GPUS (before HIP_VISIBLE_DEVICES filtering):
#   (in host: ROCR_VISIBLE_DEVICES="" rocminfo | grep -E "Name|gfx")
#   Inside if you unset the filter:
#   ROCR_VISIBLE_DEVICES="" HIP_VISIBLE_DEVICES="" rocminfo | grep gfx
#
# RECOMMENDED STABLE COMMAND (single W6800):
#   ./llama-server -m /models/... \
#       --ctx-size 160000 --gpu-layers 999 --flash-attn on \
#       --host 0.0.0.0 --no-mmap --threads 16 --temp 1.0 --top-p 0.95 \
#       --top-k 20 --min-p 0.0 --presence-penalty 0.0 --repeat-penalty 1.0 \
#       --jinja --cache-type-k q5_0 --cache-type-v q5_0 --slot-save-path /tmp \
#       --batch-size 4096 --ubatch-size 128 --parallel 1
#
# DUAL GPU (experimental):
#   podman run ... -e ROCR_VISIBLE_DEVICES=0,1 -e HIP_VISIBLE_DEVICES=0,1 ...
#   Then: HSA_ENABLE_SDMA=0 ./llama-server -m ... --split-mode layer \
#       --tensor-split 27,5 --gpu-layers 999 ...
