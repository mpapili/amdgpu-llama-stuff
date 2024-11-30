#! /bin/bash

# NOTE - you can always just add your local user to the render or video groups
sudo HSA_OVERRIDE_GFX_VERSION=10.3.0 \
  ./llama-cli -m /YOUR/PATH/TO/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf  \
  -p "who is the president of poland?" --ctx-size 150 -n 250 --gpu-layers 80
