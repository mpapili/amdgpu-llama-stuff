#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:

MODEL_PATH='/models/Qwen3.5-27B-Q6_K.gguf' 

HSA_ENABLE_SDMA=0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 100000 \
  --gpu-layers 999 \
  --flash-attn on \
  --host 0.0.0.0 \
  --no-mmap \
  --threads 16 \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --presence-penalty 1.0 \
  --jinja \
  --mmproj /models/qwen3.5-27b-mmproj-F16.gguf 
