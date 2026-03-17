#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:
MODEL_PATH='/models/Qwen3-235B-A22B-Instruct-2507-Q2_K-00001-of-00002.gguf'

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 10000 \
  -v \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --mlock \
  --no-mmap \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --no-warmup \
  --n-cpu-moe 45 \
  --threads 14 \
  --temp 0.7 \
  --top-p 0.8 \
  --top-k 20 \
  --min-p 0 \
  --tensor-split 62,38 \
