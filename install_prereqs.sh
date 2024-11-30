#! /bin/bash

# NOTE - I suspect that I had rocm previously installed, this may be incomplete?
sudo apt install -y libamd-comgr2 libamdhip64-5 libhipblas0 libhipfft0 \
  libhiprand1 libhipsolver0 libhipsparse0 libhsa-runtime64-1 librccl1 \
  librocalution0 librocblas0 librocfft0 librocm-smi64-1 librocrand1 \
  librocsolver0 librocsparse0 rocm-device-libs-17 rocm-smi rocminfo \
  cmake
