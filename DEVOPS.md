# DevOps - Docker Image Management

This document covers building and managing Docker images for llama.cpp with ROCm and Vulkan support.

## Quick Rebuild

To perform a clean rebuild that removes old images, clears cache, and rebuilds:

### ROCm Image
```bash
cd devops
./rebuild-rocm-image.sh
```
Rebuilds: `fedora-llama-cpp:latest`

### Vulkan Image
```bash
cd devops
./rebuild-vulkan-image.sh
```
Rebuilds: `fedora-llama-cpp-vulkan:latest`

## What the Rebuild Scripts Do

Both `rebuild-rocm-image.sh` and `rebuild-vulkan-image.sh`:

1. **Remove old image** - Deletes any existing image with the target tag
2. **Clear builder cache** - Runs `docker builder prune --all --force` to eliminate cached layers
3. **Fresh build** - Performs a clean rebuild from scratch using the appropriate Dockerfile

This ensures you get the latest dependencies and eliminates any stale cached state.

## Dockerfiles

### `Dockerfile.fedora` (ROCm)
- Base: Fedora 42
- Installs: ROCm tools, rocminfo, hipblas, hipfft, and other AMDGPU libraries
- Clones and builds llama.cpp with `-DGGML_HIP=ON` for ROCm support
- Target GPU: gfx1030 (adjust `AMDGPU_TARGETS` as needed)

### `Dockerfile.fedora-vulkan`
- Base: Fedora 42
- Installs: Vulkan development libraries and tools
- Alternative backend for Vulkan-enabled systems
- May have lower overhead than ROCm on some configurations

## Manual Build (without rebuild scripts)

To build without using the convenience scripts:

```bash
# ROCm build
docker build -f Dockerfile.fedora -t fedora-llama-cpp:latest .

# Vulkan build
docker build -f Dockerfile.fedora-vulkan -t fedora-llama-cpp-vulkan:latest .
```

## Running Built Images

Everything is self-contained in the built image (llama.cpp, qwen runners, API utilities).

```bash
# Use the provided script (port-forwarding already configured)
./fedora-run-docker.sh

# Or manual docker run
docker run --rm \
    --name llama-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    -v /path/to/models:/models:Z \
    -p 0.0.0.0:8080:8080 \
    -p 0.0.0.0:9090:9090 \
    fedora-llama-cpp:latest \
    /bin/bash
```

Inside the container:
```bash
# List available runners
ls qwen*.sh

# Start the API (uses qwen3.5-27b-q4.sh by default)
python3 mike-utils/llama-server-api.py

# Or with a different runner
STARTUP_SCRIPT=./qwen3.5-35b-q4.sh python3 mike-utils/llama-server-api.py
```

From your host, control via HTTP:
```bash
./llama-server-control-api.sh bounce localhost:9090
curl -X POST http://localhost:9090/bounce
curl http://localhost:9090/status | jq
```

## Customization

### Change Default GPU Target
Edit the Dockerfile before building:
```dockerfile
# In Dockerfile.fedora, change AMDGPU_TARGETS:
cmake -S .. -B build \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx1100 \  # Change this
    ...
```

Common targets:
- `gfx900` - Radeon VII, MI25, MI100
- `gfx906` - Radeon RX 5700 XT, MI50, MI60
- `gfx908` - MI100, MI110
- `gfx90a` - MI200 series (gfx90a), MI210, MI250
- `gfx1030` - RDNA 2 (RX 6600, 6700, 6800, etc.)
- `gfx1100` - RDNA 3 (RX 7600, 7700, 7800, etc.)

## Troubleshooting

**Build fails with "missing dependencies"**
- Ensure Docker has access to sufficient disk space
- Try: `docker system prune -a` (warning: removes all unused images)

**Image is huge**
- This is normal; ROCm and Vulkan bring large dependency trees
- Clean up old images: `docker image prune -a`

**Build cache issues**
- The rebuild scripts handle this automatically with `docker builder prune --all --force`
- For manual builds, add `--no-cache` to force a fresh build

**Runtime errors about missing devices**
- Verify device paths: `ls -la /dev/kfd /dev/dri/`
- Update docker run command with correct renderD* numbers
