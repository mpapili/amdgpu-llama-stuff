#!/bin/bash
set -e

# prereqs (already satisfied on your box, harmless to re-run)
sudo dnf install -y epel-release dkms "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)"
sudo dnf config-manager --set-enabled crb

# 1. Find the newest amdgpu-install RPM that actually exists for el/10.
#    Try current driver versions newest-first; stop at the first that returns 200.
BASE="https://repo.radeon.com/amdgpu-install"
RPM_URL=""
for VER in 31.30 30.30.3 30.30.2 30.30.1 30.20 30.10.1; do
  for EL in 10 10.1 10.2; do
    # the rpm filename embeds the version + a build suffix; list the dir to grab it
    DIR="$BASE/$VER/el/$EL/"
    NAME=$(curl -fsSL "$DIR" 2>/dev/null | grep -oE 'amdgpu-install-[0-9].*\.noarch\.rpm' | head -1)
    if [ -n "$NAME" ]; then
      RPM_URL="$DIR$NAME"
      echo "FOUND: $RPM_URL"
      break 2
    fi
  done
done

if [ -z "$RPM_URL" ]; then
  echo "No amdgpu-install RPM found for el/10. Browse https://repo.radeon.com/amdgpu-install/ manually."
  exit 1
fi

# 2. Install the installer, then the DKMS kernel module ONLY
sudo dnf install -y "$RPM_URL"
sudo amdgpu-install --usecase=dkms -y

echo ">>> Done. Reboot, then check: cat /sys/module/amdgpu/version"
