#!/usr/bin/env bash
set -euo pipefail

docker run --rm -it \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --cap-add=SYS_PTRACE \
  --shm-size=128g \
  -v /home/mike/Downloads/LLMs:/models \
  -p 8000:8000 \
  localhost/vllm-rocm-deepseek-k160:latest \
  bash
