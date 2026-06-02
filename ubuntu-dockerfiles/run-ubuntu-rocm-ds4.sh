#! /bin/bash

docker run --rm \
    --name ds4-rocm \
    --device=/dev/kfd \
    --device=/dev/dri/renderD128 \
    --device=/dev/dri/renderD129 \
    --cap-drop=ALL \
    --userns=keep-id \
    -v /home/mike/Downloads/LLMs:/models:Z \
    -w /ds4 \
    --security-opt no-new-privileges \
    --security-opt seccomp=unconfined \
    -e HIP_VISIBLE_DEVICES=0,1 \
    -e ROCR_VISIBLE_DEVICES=0,1 \
    -p 0.0.0.0:8080:8080 \
    -p 0.0.0.0:9090:9090 \
    -it ubuntu-ds4:latest \
    /bin/bash
