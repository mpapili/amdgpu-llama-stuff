#! /bin/bash

LLM_DIR="/home/mike/Downloads/LLMs"
MISTRAL_NEMO="Mistral-Nemo-Instruct-2407-Q6_K_L.gguf"
CODESTRAL="Codestral-22B-v0.1-Q6_K.gguf"
LLAMA3_8B="Meta-Llama-3.1-8B-Instruct-Q6_K.gguf"

# Codestral 22b, mostly on 6800
sudo HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
        -m ${LLM_DIR}/${CODESTRAL}  \
        --ctx-size 8000 \
        -v \
        --gpu-layers 60 \
        -ts 65,35 \
        --split-mode row

# NOTE - in order to use split-mode-row, which provides close to a 2x speed boost, you may need to apply the bios adjustments from this repo
