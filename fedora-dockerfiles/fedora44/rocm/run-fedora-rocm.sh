#!/bin/bash

echo "sudo just for ulimit -l"
sudo ulimit -l unlimited

podman run --rm \
    --name llama-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    --group-add keep-groups \
    --user $(id -u):$(id -g) \
    --ipc=host \
    --ulimit memlock=-1:-1 \
    --ulimit stack=67108864 \
    --security-opt no-new-privileges \
    --security-opt label=disable \
    --security-opt seccomp=unconfined \
    -v /home/mike/Downloads/LLMs:/models \
    -e HSA_ENABLE_SDMA=0 \
    -e HSA_DISABLE_FRAGMENT_ALLOCATOR=1 \
    -p 0.0.0.0:8080:8080 \
    -it localhost/llama-cpp-fedora-rocm \
    /bin/bash
