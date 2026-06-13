#!/bin/bash

docker run --rm \
    --name llama-vulkan \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    --group-add video \
    --group-add render \
    --group-add $(getent group video | cut -d: -f3) \
    --group-add $(getent group render | cut -d: -f3) \
    -v /home/mike/Downloads/LLMs:/models:Z \
    --user $(id -u):$(id -g) \
    --security-opt no-new-privileges \
    -p 0.0.0.0:8080:8080 \
    -it fedora-llama-cpp-vulkan:latest \
    /bin/bash
