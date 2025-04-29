sudo apt install libvulkan-dev vulkan-tools spirv-tools libshaderc-dev

# download it to downloads
wget https://sdk.lunarg.com/sdk/download/1.4.309.0/linux/vulkansdk-linux-x86_64-1.4.309.0.tar.xz
tar -xvf vulkansdk-linux-x86_64-1.4.309.0.tar.xz


mkdir build && cd build
export VULKAN_SDK=/home/mike/Downloads/1.4.309.0/x86_64 # (or wherever this lives)
export PATH=$VULKAN_SDK/bin:$PATH
export LD_LIBRARY_PATH=$VULKAN_SDK/lib:$LD_LIBRARY_PATH
export VK_ICD_FILENAMES=$VULKAN_SDK/etc/vulkan/icd.d
export VK_LAYER_PATH=$VULKAN_SDK/etc/vulkan/explicit_layer.d

cmake .. -DGGML_VULKAN=on -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
