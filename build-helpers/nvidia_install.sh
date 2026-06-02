#! /bin/bash

# from llambda gh200 instance

git clone https://github.com/ggml-org/llama.cpp.git
mkdir build && cd build

cmake .. -DLLAMA_CUDA=ON
make -j $(nproc)
