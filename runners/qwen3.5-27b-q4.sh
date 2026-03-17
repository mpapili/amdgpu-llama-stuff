#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:

MODEL_PATH='/models/Qwen3.5-27B-Q4_K_M.gguf' 

HSA_ENABLE_SDMA=0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 120000 \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --no-mmap \
  --threads 16 \
  --temp 0.5 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --presence-penalty 0.0 \
  --repeat-penalty 1.0 \
  --jinja \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --mmproj /models/qwen3.5-27b-mmproj-F16.gguf \
  --fit-target 2560,768 \
  --fit-ctx 120000
