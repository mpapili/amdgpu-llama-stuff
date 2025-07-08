#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:
MODEL_PATH="${1:-/home/mike/Downloads/LLMs/Qwen3-235B-A22B-Q2_K-00001-of-00002.gguf}"

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 8000 \
  -v \
  --split-mode row \
  --gpu-layers 34 \
  --flash-attn \
  --host 0.0.0.0 \
  --mlock \
  --no-mmap \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --no-warmup \
  --threads 30 \
  --temp 0.7 \
  --tensor-split 0.47,0.53
