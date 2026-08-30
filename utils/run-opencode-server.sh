#!/usr/bin/env bash
set -euo pipefail

# Host dir that becomes the container's HOME (config, state, cache all land here)
CHOME="$HOME/opencode-home"
# Host dir where your repos live; appears as ~/git inside the container
CODE="$HOME/Downloads/git"

mkdir -p \
  "$CHOME/.config/opencode" \
  "$CHOME/.local/share/opencode" \
  "$CHOME/.local/state/opencode" \
  "$CHOME/.cache" \
  "$CHOME/git"

# reuse your existing global config, if present
cp -n "$HOME/.config/opencode/opencode.json" "$CHOME/.config/opencode/" 2>/dev/null || true

exec podman run --rm -it \
  --name opencode-web \
  --network host \
  --userns keep-id \
  --user "$(id -u):$(id -g)" \
  --env HOME=/home/opencode \
  --workdir /home/opencode/git \
  -v "$CHOME:/home/opencode:Z" \
  -v "$CODE:/home/opencode/git:z" \
  -e OPENCODE_SERVER_USERNAME=opencode \
  -e OPENCODE_SERVER_PASSWORD='change-this-password' \
  localhost/opencode:latest \
  opencode web --hostname 0.0.0.0 --port 4096
