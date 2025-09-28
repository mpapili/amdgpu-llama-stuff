#! /bin/bash

./llama-server \
  -m /home/mike/Downloads/LLMs/gpt-oss-120b-F16.gguf \
  --threads 8 \
  --ctx-size 10000 \
  -ngl 17 \
  -fa on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --split-mode layer \
  --host 0.0.0.0 \
  --temp 0.5 \
  --jinja \
  --tensor-split 47,53
