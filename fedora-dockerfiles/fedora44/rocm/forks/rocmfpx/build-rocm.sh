#!/usr/bin/env bash
set -euo pipefail

podman build \
  --no-cache \
  --log-level=info \
  -t localhost/llama-cpp-rocmfpx-fedora-rocm \
  -f Dockerfile.fedora-rocm \
  .
