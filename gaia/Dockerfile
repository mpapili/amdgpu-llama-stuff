FROM python:3.12-slim

# Install Node.js + git
RUN apt-get update && apt-get install -y curl git \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv and amd-gaia with the [api] extra
RUN pip install uv
RUN uv pip install --system "amd-gaia[api]"

# Patch the hardcoded 127.0.0.1 → 0.0.0.0
RUN sed -i 's/host="127\.0\.0\.1"/host="0.0.0.0"/g' \
    $(python -c "import gaia.cli; print(gaia.cli.__file__)")

# Clone the repo
RUN git clone --depth=1 https://github.com/amd/gaia.git /tmp/gaia-src

# Install frontend deps and build
RUN cd /tmp/gaia-src/src/gaia/apps/webui && npm ci
RUN cd /tmp/gaia-src/src/gaia/apps/webui && npm run build

# Ensure target dir exists and copy dist into the installed package
RUN mkdir -p $(python -c "import gaia, os; print(os.path.join(os.path.dirname(gaia.__file__), 'apps/webui'))") \
    && cp -r /tmp/gaia-src/src/gaia/apps/webui/dist \
       $(python -c "import gaia, os; print(os.path.join(os.path.dirname(gaia.__file__), 'apps/webui/dist'))")

# Cleanup
RUN rm -rf /tmp/gaia-src

# Create a non-root user and switch to it
RUN useradd -m -u 1000 gaia-user
USER gaia-user

EXPOSE 3000

ENTRYPOINT ["gaia", "chat"]
