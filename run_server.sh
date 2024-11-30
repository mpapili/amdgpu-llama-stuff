#! /bin/bash

LLM_DIR="PATH_TO_LLM_DIR"
MISTRAL_NEMO="Mistral-Nemo-Instruct-2407-Q6_K_L.gguf"
CODESTRAL="Codestral-22B-v0.1-Q6_K.gguf"
LLAMA3_8B="Meta-Llama-3.1-8B-Instruct-Q6_K.gguf"

sudo HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
	-m ${LLM_DIR}/${MISTRAL_NEMO}  \
	-p "who is the president of poland?" \
	--ctx-size 3000 \
	--gpu-layers 80
