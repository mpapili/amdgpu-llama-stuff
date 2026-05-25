#!/bin/bash

docker run --rm \
    --name llama-vulkan \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    --userns=keep-id \
    --group-add keep-groups \
    -v /home/mike/Downloads/LLMs:/models:Z \
    --security-opt no-new-privileges \
    -p 0.0.0.0:8080:8080 \
    -it localhost/ubuntu-llama-cpp-vulkan:latest \
    /bin/bash
