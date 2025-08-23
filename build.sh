export CC=/usr/bin/hipcc
export CXX=/usr/bin/hipcc

cmake .. -G "Unix Makefiles" \
  -DGGML_HIP=ON \
  -DGGML_HIPBLAS=ON \
  -DAMDGPU_TARGETS=gfx1030 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DGGML_OPENMP=ON \
  -DGGML_LTO=OFF \
  -DLLAMA_CURL=OFF

# Build only the main CLI
make -j"$(nproc)" llama-cli

