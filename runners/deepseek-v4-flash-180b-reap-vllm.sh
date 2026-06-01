#!/usr/bin/env bash
set -euo pipefail

# vLLM server for DeepSeek-V4-Flash-180B (K160 REAP pruned)
# Hardware: W6800 (32GB, gfx1030) + RX 6800 (16GB, gfx1030) = 48GB VRAM
# Model:    ~103GB on disk (BF16) — 48GB VRAM + 55GB CPU offload
#
# If it OOMs during weight load:
#   - raise CPU_OFFLOAD_GB to 60 and lower GPU_MEM_UTIL to 0.85
# If decode is too slow (heavy CPU offload):
#   - lower MAX_MODEL_LEN to reduce KV cache pressure

MODEL_PATH="${1:-/models/deepseek-v4-flash-reap-180b}"
PORT="${PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.90}"
# With TP=2, cpu_offload_gb applies PER WORKER. 2 workers × budget must fit in
# system RAM (96GB). Budget=40 → max 80GB CPU total, leaving ~16GB for OS/other.
CPU_OFFLOAD_GB="${CPU_OFFLOAD_GB:-74}"

PYTHONPATH=/workspace/vllm \
VLLM_WEIGHT_OFFLOADING_DISABLE_UVA=1 \
VLLM_WEIGHT_OFFLOADING_DISABLE_PIN_MEMORY=1 \
# GPU[1] = W6800 (32GB), GPU[0] = RX 6800 (16GB).
# Single-GPU on W6800: 28.8GB VRAM + ~74GB CPU offload = 103GB total.
# Use TP=2 by setting TP_SIZE=2 and HIP_DEVICES=0,1 if you want dual-GPU,
# but per-worker cpu_offload_gb must be >=38 and 2x that must fit in RAM.
HIP_VISIBLE_DEVICES="${HIP_DEVICES:-1}" \
python3 -m vllm.entrypoints.openai.api_server \
  --model "${MODEL_PATH}" \
  --served-model-name DeepSeek-V4-Flash \
  --trust-remote-code \
  --dtype bfloat16 \
  --kv-cache-dtype fp8 \
  --tensor-parallel-size "${TP_SIZE:-1}" \
  --gpu-memory-utilization "${GPU_MEM_UTIL}" \
  --cpu-offload-gb "${CPU_OFFLOAD_GB}" \
  --max-model-len "${MAX_MODEL_LEN}" \
  --max-num-seqs 1 \
  --max-num-batched-tokens "${MAX_MODEL_LEN}" \
  --port "${PORT}" \
  --host 0.0.0.0
