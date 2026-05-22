#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-llama.sh [MODEL_PATH]
# Default model path if none provided:
MODEL_PATH='/models/Qwen3.5-REAP-212B-A17B-IQ3_XS-00001-of-00003.gguf'

# cpu moe 35 + 70,30 == 13.8G and 24.6G
# cpu moe 35 + 65,35 == 9.8G and 28.5G
# CPU MOE 32 + 65,35 == 13.6G AND 28.6G
#   loaded is ~15G and 29.4G (not bad..)
#     ~ 10 tokens/second but plummets fast and contexts adds memory FAST.
#     4G to spare.. can we get it to 2G on each card and bump context?


HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
  -m "${MODEL_PATH}" \
  --ctx-size 70000 \
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
  --temp 0.7 \
  --top-p 0.8 \
  --top-k 20 \
  --min-p 0 \
  --n-cpu-moe 35 \
  --tensor-split 65,35