#!/usr/bin/env bash
set -euo pipefail

# DeepSeek-V4-Flash-180B REAP Q2 via llama.cpp
# 54GB GGUF — W6800 (32GB) + RX 6800 (16GB) = 48GB VRAM, ~6GB to CPU
#
# Tuning notes (update as you test):
# tensor-split 65,35 puts ~35GB on W6800, ~19GB on RX 6800
# n-cpu-moe offloads N MoE layers to CPU — tune down if VRAM runs out,
#   up if you have headroom

MODEL_PATH="${1:-/models/DeepSeek-V4-Flash-Spark-180B-Q2-REAP-ds4.gguf}"

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 8192 \
  -v \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --mlock \
  --no-mmap \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --no-warmup \
  --threads 14 \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0 \
  --n-cpu-moe 8 \
  --tensor-split 65,35
