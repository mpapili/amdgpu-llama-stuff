#! /bin/bash

git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp/
mkdir build
cd build

HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
  cmake -S .. -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1030 \
  -DCMAKE_BUILD_TYPE=Release \
  && cmake --build build --config Release -- -j 30
