#!/usr/bin/env bash
set -euo pipefail

# rdna3 regression
# ---------------------------------------------------------------------------
# TEMPORARY PIN: last-known-good commit.
#
# Upstream llama.cpp regresses on RDNA3 GPUs past this commit, so the build is
# pinned to it until the regression is resolved. Remove/blank this once fixed.
# ---------------------------------------------------------------------------
PINNED_COMMIT=""

BUILD_ARGS=()
if [ -n "${PINNED_COMMIT}" ]; then
  echo "======================================================================"
  echo "  ***  WARNING: BUILDING AN OLDER, PINNED COMMIT  ***"
  echo "----------------------------------------------------------------------"
  echo "  Instead of the tip of the branch, llama.cpp will be built from the"
  echo "  pinned last-known-good commit (rdna3 regression workaround):"
  echo ""
  echo "      ${PINNED_COMMIT}"
  echo ""
  echo "  This is intentional and TEMPORARY. You are NOT building the latest"
  echo "  code. If you are okay building this OLDER commit, press 'y'."
  echo "  Anything else aborts the build."
  echo "======================================================================"
  read -r -n 1 -p "Build older pinned commit ${PINNED_COMMIT}? [y/N] " answer
  echo
  if [ "${answer}" != "y" ] && [ "${answer}" != "Y" ]; then
    echo "Aborted: not building the older pinned commit."
    exit 1
  fi
  BUILD_ARGS+=(--build-arg "PINNED_COMMIT=${PINNED_COMMIT}")
fi

podman build . -f Dockerfile.fedora-vulkan -t llama-cpp-fedora-vulkan "${BUILD_ARGS[@]}"
