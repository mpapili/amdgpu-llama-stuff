#! /bin/bash

podman run --rm \
    --name llama-cpp-rocky-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    --cap-add=SYS_PTRACE \
    --cap-add=IPC_LOCK \
    -v /home/mike/Downloads/LLMs:/models:Z \
    -w /llama.cpp/build/build/bin \
    --user $(id -u):$(id -g) \
    --security-opt no-new-privileges \
    --security-opt seccomp=unconfined \
    -e HIP_VISIBLE_DEVICES=0,1 \
    -e ROCR_VISIBLE_DEVICES=0,1 \
    -p 0.0.0.0:8080:8080 \
    -it localhost/llama-cpp-rocky-rocm \
    /bin/bash
