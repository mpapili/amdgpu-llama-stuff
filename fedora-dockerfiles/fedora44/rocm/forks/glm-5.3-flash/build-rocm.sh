#! /bin/bash

podman build \
  --no-cache \
  --log-level=info \
  -t localhost/llama-cpp-glm5next-fedora-rocm \
  -f Dockerfile.fedora-rocm \
  .
