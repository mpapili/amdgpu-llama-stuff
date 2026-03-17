#! /bin/bash

./llama-server --ctx-size 75000 -v --gpu-layers 999 --flash-attn on --host 0.0.0.0 --mlock --no-mmap --cache-type-k q8_0 --cache-type-v q8_0 --jinja --no-warmup --threads 8 --temp 0.2 --top-p 0.95 --top-k 20 --min-p 0 --repeat-penalty 1.05 --tensor-split 30,70 --jinja --models-dir /models/ --timeout 99999
