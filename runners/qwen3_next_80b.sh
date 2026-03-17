#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:
MODEL_PATH='/models/Qwen3-Next-80B-A3B-Instruct-Q5_K_S-00001-of-00002.gguf'

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 75000 \
  -v \
  --gpu-layers 150 \
  --flash-attn on \
  --host 0.0.0.0 \
  --mlock \
  --no-mmap \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja \
  --no-warmup \
  --n-cpu-moe 33 \
  --threads 8 \
  --temp 0.5 \
  --top-p 0.8 \
  --top-k 0.2 \
  --repeat-penalty 1.05 \
  --tensor-split 80,20 \
  --jinja
