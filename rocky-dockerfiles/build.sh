TMPDIR=$(pwd)/buildtmp podman build . -f Dockerfile.rocky-rocm -t llama-cpp-rocky-rocm
