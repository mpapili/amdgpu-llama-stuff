#!/usr/bin/env bash
set -euo pipefail

# rebuild-rocm-image-ubuntu-ds4.sh - Clean rebuild of ds4 ROCm Docker image
# Rebuilds with tag ubuntu-ds4:latest
# Run from project root: ./devops/rebuild-rocm-image-ubuntu-ds4.sh

# Get the project root (parent of devops directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

IMAGE_TAG="ubuntu-ds4:latest"
DOCKERFILE="Dockerfile.ubuntu-rocm-ds4"

echo "========================================"
echo "ds4 ROCm Image Rebuild"
echo "========================================"
echo "Project root: $PROJECT_ROOT"
echo "Image tag: $IMAGE_TAG"
echo "Dockerfile: $DOCKERFILE"
echo ""

# Check if Dockerfile exists
if [[ ! -f "$DOCKERFILE" ]]; then
    echo "ERROR: $DOCKERFILE not found in $PROJECT_ROOT"
    exit 1
fi

# Delete existing image
echo "Step 1/3: Removing old image '$IMAGE_TAG'..."
if podman image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    docker image rm "$IMAGE_TAG" --force
    echo "✓ Old image removed"
else
    echo "✓ No existing image found (skipping)"
fi

# Clear builder cache
echo ""
echo "Step 2/3: Clearing Docker builder cache..."
podman builder prune --all --force
echo "✓ Builder cache cleared"

# Rebuild image
echo ""
echo "Step 3/3: Building new image..."
podman build \
    --file "$DOCKERFILE" \
    --tag "$IMAGE_TAG" \
    --progress=plain \
    "$PROJECT_ROOT"

if podman image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    echo ""
    echo "========================================"
    echo "✓ Build successful!"
    echo "Image ready: $IMAGE_TAG"
    echo "========================================"
else
    echo ""
    echo "✗ Build failed"
    exit 1
fi
