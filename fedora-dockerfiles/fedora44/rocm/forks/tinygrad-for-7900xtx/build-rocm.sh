#! /bin/bash

podman build \
  --no-cache \
  --log-level=info \
  -t localhost/tinygrad-am-fedora \
  -f Dockerfile.fedora-rocm \
  .
