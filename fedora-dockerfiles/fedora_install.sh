#!/bin/bash

echo "Updating system packages..."
sudo dnf update -y

echo "Installing essential ROCm utilities and tools..."
sudo dnf install -y \
  rocminfo \
  rocm-clinfo \
  rocm-opencl \
  radeontop \
  git

echo "Installing ROCm libraries and dependencies..."
sudo dnf install -y \
  rocm-comgr \
  rocblas-devel \
  hipblas \
  hipblas-devel \
  hipfft \
  hiprand \
  hipsolver \
  hipsparse \
  rocalution \
  rocblas \
  rocfft \
  rocm-smi \
  rocrand \
  rocsolver \
  rocsparse \
  rocm-device-libs \
  rocminfo \
  cmake

echo "Installing HIP compiler and development tools..."
sudo dnf install -y \
  rocm-hip \
  rocm-hip-devel --enable-repo=updates-testing

echo "Installation completed successfully!"
