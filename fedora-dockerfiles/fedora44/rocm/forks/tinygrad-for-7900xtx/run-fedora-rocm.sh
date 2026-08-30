#!/usr/bin/env bash
set -euo pipefail

# tinygrad AM on the 7900 XTX. Exclusive BAR ownership.
# Unbinds ONLY the XTX VGA + HDMI audio. Never rmmod amdgpu.
# Never fuser -k: GNOME/KDE keep both GPUs open, so that kills the session.

XTX_DID="0x744c"
IMAGE="${IMAGE:-localhost/tinygrad-am-fedora}"
MODELS_DIR="${MODELS_DIR:-/home/mike/Downloads/LLMs}"
CACHE_DIR="${CACHE_DIR:-${HOME}/.cache/tinygrad}"
HOST_GGUF="${HOST_GGUF:-/home/mike/Downloads/LLMs/Qwen3.8-27B-IQ4_XS.gguf}"
MODEL="${MODEL:-/models/$(basename "${HOST_GGUF}")}"
PORT="${PORT:-8080}"

xtx_pci=""
xtx_aud=""
disp_pci=""
disp_did=""
disp_driver=""

for pci_path in /sys/bus/pci/devices/*; do
    [[ -f "${pci_path}/vendor" && -f "${pci_path}/device" && -f "${pci_path}/class" ]] || continue
    [[ $(<"${pci_path}/vendor") == "0x1002" ]] || continue
    did=$(<"${pci_path}/device")
    class=$(<"${pci_path}/class")
    pci=$(basename "${pci_path}")
    driver=""
    if [[ -e "${pci_path}/driver" ]]; then
        driver=$(basename "$(readlink "${pci_path}/driver")")
    fi

    if [[ "${did}" == "${XTX_DID}" ]]; then
        xtx_pci="${pci}"
        slot="${pci%.*}"
        for fn in 1 2 3 4 5 6 7; do
            sib="${slot}.${fn}"
            sib_path="/sys/bus/pci/devices/${sib}"
            [[ -f "${sib_path}/class" ]] || continue
            if [[ $(<"${sib_path}/class") == 0x040300 ]]; then
                xtx_aud="${sib}"
                break
            fi
        done
    elif [[ "${class}" == 0x030000 ]]; then
        disp_pci="${pci}"
        disp_did="${did}"
        disp_driver="${driver}"
    fi
done

if [[ -z "${xtx_pci}" ]]; then
    echo "ERROR: no 7900 XTX (${XTX_DID}) found."
    exit 1
fi

if [[ -z "${disp_pci}" ]]; then
    echo "ERROR: no second AMD VGA found. Refusing to unbind the XTX."
    echo "GPUs:"
    lspci -nnk -d 1002: || true
    exit 1
fi

if [[ "${disp_driver}" != "amdgpu" ]]; then
    echo "ERROR: display GPU ${disp_pci} (${disp_did}) driver is '${disp_driver:-none}', not amdgpu."
    exit 1
fi

xtx_has_display=0
for status in /sys/bus/pci/devices/${xtx_pci}/drm/card*/card*-*/status; do
    [[ -f "${status}" ]] || continue
    if [[ $(<"${status}") == "connected" ]]; then
        xtx_has_display=1
    fi
done

if [[ "${xtx_has_display}" == "1" && "${FORCE:-0}" != "1" ]]; then
    echo "ERROR: 7900 XTX (${xtx_pci}) still has a connected display."
    echo "Plug the monitor into the other GPU (${disp_pci}), then re-run. FORCE=1 skips this."
    exit 1
fi

echo "XTX ${xtx_pci} ${XTX_DID}  display ${disp_pci} ${disp_did} ${disp_driver}"

xtx_devs=()
for node in /sys/bus/pci/devices/${xtx_pci}/drm/renderD* /sys/bus/pci/devices/${xtx_pci}/drm/card*; do
    [[ -e "${node}" ]] || continue
    xtx_devs+=( "/dev/dri/$(basename "${node}")" )
done

holders=""
if ((${#xtx_devs[@]})); then
    holders=$(sudo fuser "${xtx_devs[@]}" 2>/dev/null || true)
fi

if [[ -n "${holders// /}" && "${FORCE:-0}" != "1" ]]; then
    echo "ERROR: compositor still has the XTX open. Unbind would kill the session."
    echo "Holders of ${xtx_devs[*]}:"
    sudo fuser -v "${xtx_devs[@]}" 2>/dev/null || true
    echo
    echo "GNOME/KDE open every DRM node even when the monitor is on the W6800."
    echo "From a TTY (Ctrl+Alt+F3), not a GUI terminal:"
    echo "  sudo systemctl stop gdm    # or sddm / lightdm"
    echo "  ./run-fedora-rocm.sh"
    echo "  # when done: sudo systemctl start gdm"
    echo "FORCE=1 skips this check (will log you out)."
    exit 1
fi

unbind_xtx() {
    if [[ -n "${xtx_aud}" && -e "/sys/bus/pci/devices/${xtx_aud}/driver" ]]; then
        echo "${xtx_aud}" | sudo tee "/sys/bus/pci/devices/${xtx_aud}/driver/unbind" >/dev/null
    fi
    if [[ -e "/sys/bus/pci/devices/${xtx_pci}/driver" ]]; then
        echo "${xtx_pci}" | sudo tee "/sys/bus/pci/devices/${xtx_pci}/driver/unbind" >/dev/null
    fi
    if [[ -e "/sys/bus/pci/devices/${xtx_pci}/driver" ]]; then
        echo "ERROR: XTX still bound after unbind (device busy)."
        echo "A process still holds it. Stop the display manager from a TTY first."
        exit 1
    fi
    echo "unbound XTX ${xtx_pci}  display ${disp_pci} still ${disp_driver}"
    lspci -nnk -s "${xtx_pci#0000:}" || true
    lspci -nnk -s "${disp_pci#0000:}" || true
}

finish_xtx() {
    if [[ "${RESTORE_XTX:-0}" != "1" ]]; then
        echo "leaving XTX ${xtx_pci} unbound for repeatable AM use"
        return
    fi
    echo | sudo tee "/sys/bus/pci/devices/${xtx_pci}/driver_override" >/dev/null || true
    if [[ ! -e "/sys/bus/pci/devices/${xtx_pci}/driver" ]]; then
        echo "${xtx_pci}" | sudo tee /sys/bus/pci/drivers/amdgpu/bind >/dev/null || \
            echo 1 | sudo tee /sys/bus/pci/rescan >/dev/null || true
    fi
    # tinygrad removes the GPU's sibling PCI functions while it owns the card.
    # Rescan before restoring HDMI audio so 04:00.1 exists again.
    echo 1 | sudo tee /sys/bus/pci/rescan >/dev/null || true
    if [[ -n "${xtx_aud}" && ! -e "/sys/bus/pci/devices/${xtx_aud}/driver" ]]; then
        audio_rebound=0
        for _ in {1..5}; do
            if echo "${xtx_aud}" | sudo tee /sys/bus/pci/drivers/snd_hda_intel/bind >/dev/null 2>&1; then
                audio_rebound=1
                break
            fi
            sleep 1
        done
        if [[ "${audio_rebound}" == "0" ]]; then
            echo "WARNING: HDMI audio ${xtx_aud} did not rebind; the XTX itself was still restored."
        fi
    fi
    echo "rebind attempted for ${xtx_pci}"
    lspci -nnk -s "${xtx_pci#0000:}" || true
}

trap finish_xtx EXIT

mkdir -p "${CACHE_DIR}"

if [[ ! -f "${HOST_GGUF}" ]]; then
    echo "ERROR: host GGUF not found: ${HOST_GGUF}"
    exit 1
fi
if [[ "$(realpath "${HOST_GGUF}")" != "$(realpath "${MODELS_DIR}/$(basename "${HOST_GGUF}")")" ]]; then
    echo "ERROR: ${HOST_GGUF} is not inside MODELS_DIR=${MODELS_DIR}"
    exit 1
fi

# Rootless podman cannot open PCI sysfs even with --privileged. AM needs real
# root, so keep the separately stored rootful image in sync with each rebuild.
rootless_image_id=$(podman image inspect --format '{{.Id}}' "${IMAGE}")
rootful_image_id=$(sudo podman image inspect --format '{{.Id}}' "${IMAGE}" 2>/dev/null || true)
if [[ "${rootless_image_id}" != "${rootful_image_id}" ]]; then
    echo "Updating ${IMAGE} in rootful podman storage..."
    podman save "${IMAGE}" | sudo podman load
fi

unbind_xtx

# --network host: container 0.0.0.0:${PORT} is the host. Do not exec; the trap
# preserves AM ownership by default or restores amdgpu with RESTORE_XTX=1.
sudo podman run --rm -it \
    --name tiny-am \
    --privileged \
    --network host \
    --security-opt label=disable \
    -e DEV=PCI+AMD \
    -e AM_RESET=1 \
    -e AM_DEBUG=2 \
    -e DEBUG=2 \
    -e JITBEAM=2 \
    -e HOME=/root \
    -v "${CACHE_DIR}:/root/.cache/tinygrad:Z" \
    -v "${MODELS_DIR}:/models:Z" \
    "${IMAGE}" \
    python3 -m tinygrad.llm --model "${MODEL}" --serve "${PORT}"
