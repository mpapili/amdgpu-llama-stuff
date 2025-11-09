#! /bin/bash

docker run --rm \
    --name llama-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    -v /home/mike/Downloads/git/llama.cpp:/llama-cpp:Z \
    -v /home/mike/Downloads/LLMs:/models:Z \
    -w /llama-cpp \
    --user $(id -u):$(id -g) \
    --security-opt no-new-privileges \
    -e HIP_VISIBLE_DEVICES=0,1 \
    -e ROCR_VISIBLE_DEVICES=0,1 \
    -p 0.0.0.0:8080:8080 \
    -it fedora-llama-cpp:latest \
    /bin/bash
