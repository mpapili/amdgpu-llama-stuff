# Sample Commands

Run these commands from the directory containing the scripts.

## Build the image

```bash
./rebuild-vllm-rocm.sh
```

The rebuild uses `--pull=always`, so Podman checks for a newer
`vllm/vllm-openai-rocm:latest` base image instead of relying only on a cached copy.
The image then upgrades `transformers` and `bitsandbytes` using the ROCm
PyTorch wheel index as an additional package source.

## Check installed versions

From the Bash shell, check the versions actually installed in the image:

```bash
python -c 'import vllm, transformers; print("vLLM:", vllm.__version__); print("Transformers:", transformers.__version__)'
```

You can also inspect the base image timestamp from the host:

```bash
podman image inspect vllm/vllm-openai-rocm:latest \
  --format '{{.Id}} {{.Created}}'
```

## Start a Bash shell in the container

This mounts the host model directory at `/models`, exposes both AMD GPU
devices, and publishes container port `8081` on host port `8081`.

```bash
./run-vllm-rocm.sh
```

## Start vLLM from inside the container

After the Bash shell starts, run a command like this. Replace the filename
with the GGUF stored in `~/Downloads/LLMs/` on the host.

```bash
vllm serve /models/my-model.gguf \
  --host 0.0.0.0 \
  --port 8081 \
  --tensor-parallel-size 2
```

`--tensor-parallel-size 2` tells vLLM to use both exposed GPUs. The W6800
and RX 7900 XTX have different GPU architectures, so heterogeneous tensor
parallelism may still be limited by the model, ROCm, or vLLM backend.

The API will then be available on the host at:

```text
http://127.0.0.1:8081
```

## Serve Gemma 4 with bitsandbytes

From inside the container, the following serves the Hugging Face model using
bitsandbytes quantization:

```bash
vllm serve google/gemma-4-26B-A4B-it \
  --quantization bitsandbytes \
  --dtype auto \
  --gpu-memory-utilization 0.90 \
  --max-model-len 4096 \
  --enforce-eager \
  --hf-overrides '{"allow_global_per_layer_attribute_access": true}' \
  --hf-overrides '{"text_config": {"allow_global_per_layer_attribute_access": true}}' \
  --limit-mm-per-prompt '{"image":0,"audio":0}'
```

To explicitly use both exposed GPUs, add:

```bash
  --tensor-parallel-size 2
```

## Optional overrides

Use a different model directory, image tag, container name, or host port by
setting environment variables before starting the shell:

```bash
VLLM_ROCM_MODEL_DIR="$HOME/Downloads/LLMs" \
VLLM_ROCM_IMAGE="localhost/vllm-rocm:latest" \
VLLM_ROCM_CONTAINER="vllm-rocm" \
VLLM_ROCM_PORT=8081 \
./run-vllm-rocm.sh
```
