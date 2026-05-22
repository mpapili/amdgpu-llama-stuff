docker run -it --rm \
  --name gaia-ui \
  -p 3000:3000 \
  -w /home/gaia-user \
  --cap-drop ALL \
  --security-opt no-new-privileges=true \
  --read-only \
  --tmpfs /tmp:mode=1777 \
  --tmpfs /home/gaia-user:uid=1000,mode=1777 \
  --add-host host.docker.internal:host-gateway \
  local-gaia --base-url http://host.docker.internal:9091 --ui --ui-port 3000
