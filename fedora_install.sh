#! /bin/bash

sudo dnf update -y
sudo dnf install -y \
  rocminfo \
  rocm-clinfo \
  rocm-opencl \
  radeontop \
  git

sudo dnf install -y rocm-comgr rocblas-devel hipblas hipblas-devel hipfft hiprand hipsolver hipsparse rocalution rocblas rocfft rocm-smi rocrand rocsolver rocsparse rocm-device-libs  rocminfo cmake 

sudo dnf install rocm-hip rocm-hip-devel --enable-repo=updates-testing -y

