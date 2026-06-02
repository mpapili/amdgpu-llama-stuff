# 1. Build prereqs
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb
sudo dnf install -y dkms "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)"

# 2. amdgpu repo — note: 'el' not 'rhel', and a real DRIVER version with an el/10 build
sudo tee /etc/yum.repos.d/amdgpu.repo >/dev/null <<'EOF'
[amdgpu]
name=amdgpu
baseurl=https://repo.radeon.com/amdgpu/30.30.3/el/10/main/x86_64/
enabled=1
priority=50
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
EOF

# 3. kernel module only
sudo dnf clean all
sudo dnf install -y amdgpu-dkms


# 4. Reboot so DKMS amdgpu replaces the in-tree module
echo "reboot now"
###sudo reboot
