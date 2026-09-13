#!/bin/bash

echo "sudo just for ulimit -l"
sudo ulimit -l unlimited

# maximum perf
# Force AMD GPUs into their high-performance state
for f in /sys/class/drm/card[0-9]*/device/power_dpm_force_performance_level; do
    [ -w "$f" ] && echo high | sudo tee "$f"
done

sudo tuned-adm profile accelerator-performance

mkdir -p "$HOME/.cache/llama-vulkan"

# Critical: Vulkan always requires disabling host-visible VRAM.
podman run --rm \
    --name llama-vulkan \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --device=/dev/kfd \
    --group-add keep-groups \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --user "$(id -u):$(id -g)" \
    --ulimit memlock=-1:-1 \
    -e XDG_CACHE_HOME=/cache \
    -e MESA_SHADER_CACHE_DIR=/cache \
    -e GGML_VK_VISIBLE_DEVICES=0,1 \
    -e GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1 \
    -v "$HOME/.cache/llama-vulkan:/cache:Z" \
    -v /home/mike/Downloads/LLMs:/models:Z \
    -p 0.0.0.0:8080:8080 \
    -it localhost/llama-cpp-fedora-vulkan \
    /bin/bash
