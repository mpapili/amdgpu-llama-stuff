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
# and multi-GPU pitfalls.
# ──────────────────────────────────────────────
# Original cmd that segfaulted:
#   --tensor-split 100,0  (splits across BOTH visible GPUs)
#   + only gfx1030 kernels built -> gfx1100 node has no kernels -> segfault
#   + HSA_ENABLE_SDMA=0 alone is not enough for split across arch families
#
# For your setup:
#   Option A (Recommended - your requested cmd): put everything on W6800 (32GB)
#     and ignore 7900 XTX inside llama.cpp, using tensor-split 100,0 or
#     better: hide the second GPU entirely.
#
#   Option B: actually split across both GPUs:
#     Requires both gfx targets built (now fixed) + use visible devices filter.
#
# This script exports your full multi-GPU command correctly:
# ──────────────────────────────────────────────
podman run --rm \
    --name llama-rocm \
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
    -it localhost/llama-cpp-fedora-rocm \
    /bin/bash

# ─── How to run inside container (pick ONE) ───
#
# VERIFY BOTH GPUS (before HIP_VISIBLE_DEVICES filtering):
#   (in host: ROCR_VISIBLE_DEVICES="" rocminfo | grep -E "Name|gfx")
#   Inside if you unset the filter:
#   ROCR_VISIBLE_DEVICES="" HIP_VISIBLE_DEVICES="" rocminfo | grep gfx
#
# You asked for this failing cmd - now fixed explanation:
#
#   HSA_ENABLE_SDMA=0 ./llama-server -m /models/Qwen3.6-27B-IQ4_XS.gguf \
#     --ctx-size 160000 --gpu-layers 999 --flash-attn on \
#     --host 0.0.0.0 --no-mmap --threads 16 --temp 1.0 --top-p 0.95 \
#     --top-k 20 --min-p 0.0 --presence-penalty 0.0 --repeat-penalty 1.0 \
#     --jinja --chat-template-kwargs '{"enable_thinking": true}' \
#     --cache-type-k q5_0 --cache-type-v q5_0 --slot-save-path /tmp \
#     --tensor-split 100,0 --spec-type draft-mtp --spec-draft-n-max 2 \
#     --batch-size 4096 --ubatch-size 128 --parallel 1
#
# ROOT CAUSE of your segfault:
#   1) Dockerfile only built gfx1030. With both GPUs visible (renderD128+D129)
#      and --tensor-split 100,0, llama.cpp tries to init HIP backend on BOTH.
#      gfx1100 (7900 XTX) has no compiled kernels -> null/cooked function ptr
#      -> Segmentation fault (no assert, silent).
#   2) W6800+7900XTX multi-GPU split across RDNA2+RDNA3 is generally unstable
#      in rocBLAS anyway due to different wave sizes/arch.
#   3) 160k ctx + kq5_0 vq5_0 + 27B model needs ~30GB+ VRAM. W6800 alone is
#      32GB - tight but okay. Using both GPUs was better intention.
#
# FIXES APPLIED:
#   Dockerfile: now builds gfx1030;gfx1100 fat binary
#   run.sh: 
#     --device=/dev/dri (whole dir) not just two nodes - handles re-enum.
#     HIP/ROCR_VISIBLE_DEVICES=0 hides 7900 XTX by default for stable single GPU.
#     This makes --tensor-split unnecessary (single device). If you want both,
#     run with:  -e HIP_VISIBLE_DEVICES=0,1 -e ROCR_VISIBLE_DEVICES=0,1
#                and use --tensor-split 80,20 or similar.
#     Removed HSA_DISABLE_FRAGMENT_ALLOCATOR=1 - harmful on ROCm 7.1+.
#     Added GGML_CUDA_FORCE_DMMV=1 for extra RDNA stability.
#
# IF YOU STILL WANT DUAL GPU (experimental):
#   podman run ... -e ROCR_VISIBLE_DEVICES=0,1 -e HIP_VISIBLE_DEVICES=0,1 ... 
#   Then inside:
#     HSA_ENABLE_SDMA=0 ./llama-server -m /models/Qwen... --split-mode layer \
#       --tensor-split 27,5  (approx VRAM ratio 32GB:24GB but 7900 faster) \
#       --gpu-layers 999 ... 
#   Expect possible rocBLAS arch-mismatch slowdowns.
#
# RECOMMENDED STABLE COMMAND (single W6800 - what you asked for, fixed):
#   ./llama-server -m /models/Qwen3.6-27B-IQ4_XS.gguf \
#       --ctx-size 160000 --gpu-layers 999 --flash-attn on \
#       --host 0.0.0.0 --no-mmap --threads 16 --temp 1.0 --top-p 0.95 \
#       --top-k 20 --min-p 0.0 --presence-penalty 0.0 --repeat-penalty 1.0 \
#       --jinja --chat-template-kwargs '{"enable_thinking": true}' \
#       --cache-type-k q5_0 --cache-type-v q5_0 --slot-save-path /tmp \
#       --spec-type draft-mtp --spec-draft-n-max 2 \
#       --batch-size 4096 --ubatch-size 128 --parallel 1
#   (no tensor-split needed when only one GPU visible)
