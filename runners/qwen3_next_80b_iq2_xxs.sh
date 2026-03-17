#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:
MODEL_PATH='/models/Qwen3-Next-80B-A3B-Instruct-UD-IQ2_XXS.gguf'

HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 8000 \
  -v \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja \
  --no-warmup \
  --threads 8 \
  --temp 0.5 \
  --jinja
