#! /bin/bash


./llama-server -v --gpu-layers 999 --flash-attn on --host 0.0.0.0 --mlock --no-mmap --cache-type-k q8_0 --cache-type-v q8_0 --jinja --no-warmup \
	--threads 30 \
	--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --presence-penalty 0.0 --repeat-penalty 1.0 --jinja --model  /models/Qwen3.5-122B-A10B-UD-IQ2_M.gguf --timeout 99999 \
	--ctx-size 80000 \
	--mmproj /models/qwen3.5_122b_mmproj-F16.gguf \
	--tensor-split 25,75
