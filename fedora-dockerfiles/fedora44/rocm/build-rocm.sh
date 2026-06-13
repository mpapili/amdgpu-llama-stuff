#! /bin/bash

echo "MIKE YOU PINNED TO A WORKING COMMIT FROM A WEEK AGO"
sleep 5
echo "GOT IT!?"
sleep 2
podman build . -t llama-cpp-fedora-rocm -f Dockerfile.fedora-rocm
