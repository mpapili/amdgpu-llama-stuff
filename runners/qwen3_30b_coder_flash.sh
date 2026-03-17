#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:

MODEL_PATH='/models/Qwen3-Coder-30B-A3B-Instruct-Q6_K.gguf'

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 60000 \
  -v \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --threads 30 \
  --temp 0.7 \
  --top-p 0.8 \
  --top-k 20 \
  --repeat-penalty 1.05 \
  --min-p 0 \
  --jinja
