# amdgpu-llama-stuff
Useful scripts and configurations for running llama.cpp with AMDGPU (ROCm) and Vulkan support on Fedora.

## Directory Structure

- **`devops/`** - Build automation and image management scripts
  - `rebuild-rocm-image.sh` - Clean rebuild of ROCm Docker image
  - `rebuild-vulkan-image.sh` - Clean rebuild of Vulkan Docker image
- **`Dockerfile.fedora`** - Base Fedora image with ROCm support (includes Python/Flask)
- **`Dockerfile.fedora-vulkan`** - Fedora image with Vulkan backend support
- **`mike-utils/llama-server-api.py`** - HTTP API wrapper for llama-server process management
- **`mike-utils/llama-server-control-api.sh`** - CLI client for controlling API
- **Startup scripts** - Various model startup scripts (e.g., `qwen3.5-27b-q4.sh`)

## Quick Start

See **[BOUNCE_SERVER.md](BOUNCE_SERVER.md)** for server management and **[DEVOPS.md](DEVOPS.md)** for image builds.

## Files

- `bios_adjustments.md` - Hardware tuning recommendations
- `BOUNCE_SERVER.md` - Server process control documentation
- `DEVOPS.md` - Docker image build and deployment
