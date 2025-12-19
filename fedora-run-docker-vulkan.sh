#! /bin/bash

docker run --rm \
    --name llama-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    -v /home/mike/Downloads/LLMs:/models:Z \
    --user $(id -u):$(id -g) \
    --security-opt no-new-privileges \
    -p 0.0.0.0:8080:8080 \
    -it fedora-llama-cpp-vulkan:latest \
    /bin/bash
