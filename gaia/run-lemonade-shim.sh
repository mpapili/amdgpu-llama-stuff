docker run -d --rm \
  --name gaia-shim \
  --add-host host.docker.internal:host-gateway \
  -p 9091:9091 \
  -v $(pwd)/nginx-shim.conf:/etc/nginx/conf.d/default.conf:Z \
  nginx:alpine
