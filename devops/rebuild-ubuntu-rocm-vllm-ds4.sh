# 1. Build (this will take 30–90 minutes and ~40 GB disk)
# --layers=false skips the layer cache so failed attempts don't accumulate 500GB of dangling layers.
# Remove that flag once the build is stable if you want faster incremental rebuilds.
podman build --layers=false -t localhost/vllm-rocm-deepseek-k160:latest -f Dockerfile.ubuntu-rocm-vllm-ds4 .

# 2. Run (mount your model + ROCm device)
docker run --rm -it \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --cap-add=SYS_PTRACE \
  --shm-size=128g \
  -v /home/mike/Downloads/LLMs:/models \
  -p 8000:8000 \
  localhost/vllm-rocm-deepseek-k160:latest
