#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  "$HOME/.config/opencode" \
  "$HOME/.local/share/opencode" \
  "$HOME/.local/state/opencode" \
  "$HOME/.cache/opencode"

exec podman run --rm -it \
  --name opencode \
  --network host \
  --userns keep-id \
  --user "$(id -u):$(id -g)" \
  --env HOME=/home/opencode \
  --workdir /workspace \
  -v "$PWD:/workspace:Z" \
  -v "$HOME/.config/opencode:/home/opencode/.config/opencode:Z" \
  -v "$HOME/.local/share/opencode:/home/opencode/.local/share/opencode:Z" \
  -v "$HOME/.local/state/opencode:/home/opencode/.local/state/opencode:Z" \
  -v "$HOME/.cache/opencode:/home/opencode/.cache:Z" \
  -e OPENCODE_SERVER_USERNAME=opencode \
  -e OPENCODE_SERVER_PASSWORD='change-this-password' \
  -it localhost/opencode:latest opencode
