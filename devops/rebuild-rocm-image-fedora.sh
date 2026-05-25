#!/usr/bin/env bash
set -euo pipefail

# rebuild-rocm-image.sh - Clean rebuild of ROCm Docker image
# Deletes the old image, clears builder cache, and rebuilds with tag fedora-llama-cpp:latest
# Run from project root: ./devops/rebuild-rocm-image.sh

# Get the project root (parent of devops directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

IMAGE_TAG="fedora-llama-cpp:latest"
DOCKERFILE="Dockerfile.fedora"

echo "========================================"
echo "ROCm Image Rebuild"
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

# Copy qwen runner scripts from llama.cpp directory
echo "Step 1/4: Syncing qwen runner scripts..."
LLAMA_CPP_DIR="$PROJECT_ROOT/../../git/llama.cpp"
if [[ -d "$LLAMA_CPP_DIR" ]]; then
    mkdir -p "$PROJECT_ROOT/runners"
    cp "$LLAMA_CPP_DIR"/qwen*.sh "$PROJECT_ROOT/runners/" 2>/dev/null || true
    echo "✓ Synced $(ls "$PROJECT_ROOT"/runners/qwen*.sh 2>/dev/null | wc -l) qwen runners"
else
    echo "⚠ llama.cpp directory not found at $LLAMA_CPP_DIR, skipping sync"
fi

# Delete existing image
echo ""
echo "Step 2/4: Removing old image '$IMAGE_TAG'..."
if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    docker image rm "$IMAGE_TAG" --force
    echo "✓ Old image removed"
else
    echo "✓ No existing image found (skipping)"
fi

# Clear builder cache
echo ""
echo "Step 3/4: Clearing Docker builder cache..."
docker builder prune --all --force
echo "✓ Builder cache cleared"

# Rebuild image
echo ""
echo "Step 4/4: Building new image..."
docker build \
    --file "$DOCKERFILE" \
    --tag "$IMAGE_TAG" \
    --progress=plain \
    "$PROJECT_ROOT"

if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
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
