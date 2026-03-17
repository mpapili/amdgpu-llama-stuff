#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:
MODEL_PATH='/models/Qwen3-Next-80B-A3B-Thinking-Q4_K_S.gguf'

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 75000 \
  -v \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --mlock \
  --no-mmap \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja \
  --no-warmup \
  --n-cpu-moe 20 \
  --threads 8 \
  --temp 0.5 \
  --top-p 0.95 \
  --top-k 0.20 \
  --min-p 0 \
  --repeat-penalty 1.05 \
  --tensor-split 67,33 \
  --jinja
