#! /bin/bash

podman build \
  --no-cache \
  --log-level=info \
  -t localhost/llama-cpp-qwen4exp-fedora-rocm \
  -f Dockerfile.fedora-rocm \
  .