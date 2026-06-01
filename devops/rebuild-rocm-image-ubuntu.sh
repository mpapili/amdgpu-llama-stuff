#!/usr/bin/env bash
set -euo pipefail

# rebuild-rocm-image.sh - Clean rebuild of ROCm Docker image
# Rebuilds with tag ubuntu-llama-cpp:latest
# Run from project root: ./devops/rebuild-rocm-image.sh

# Get the project root (parent of devops directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

IMAGE_TAG="ubuntu-llama-cpp:latest"
DOCKERFILE="Dockerfile.ubuntu-rocm"

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
echo "Step 1/2: Syncing qwen runner scripts..."
LLAMA_CPP_DIR="$PROJECT_ROOT/../../git/llama.cpp"
if [[ -d "$LLAMA_CPP_DIR" ]]; then
    mkdir -p "$PROJECT_ROOT/runners"
    cp "$LLAMA_CPP_DIR"/qwen*.sh "$PROJECT_ROOT/runners/" 2>/dev/null || true
    echo "✓ Synced $(ls "$PROJECT_ROOT"/runners/qwen*.sh 2>/dev/null | wc -l) qwen runners"
else
    echo "⚠ llama.cpp directory not found at $LLAMA_CPP_DIR, skipping sync"
fi

# Rebuild image
# systemd-run cgroup limits prevent the build from saturating CPU and disk I/O.
# CPUQuota=400% = 4 cores max; MemoryMax=32G; IOWeight=10 = low disk priority (default 100).
echo ""
echo "Step 2/2: Building new image (CPU ≤4 cores, RAM ≤32G, low IO priority)..."
systemd-run --scope \
    -p CPUQuota=400% \
    -p MemoryMax=32G \
    -p IOWeight=10 \
    -- podman build \
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
