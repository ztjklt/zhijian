# Build context and Railway service root: ZSCB/.
FROM debian:bookworm-slim
ARG GODOT_VERSION=4.6.3
ARG GODOT_SHA512=a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip python3 libfontconfig1 libx11-6 libxcursor1 \
    libxinerama1 libgl1 libxi6 libxrandr2 libasound2 fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*
# Exact official release, not a moving 'latest' URL. Verify the release checksum.
RUN cd /tmp \
    && curl -fL --retry 3 -o godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && printf '%s  godot.zip\n' "$GODOT_SHA512" > checksum.txt \
    && sha512sum -c checksum.txt \
    && unzip -q godot.zip && mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot && rm -f godot.zip checksum.txt
WORKDIR /app
COPY project.godot /app/
COPY scripts /app/scripts
COPY scenes /app/scenes
COPY animations /app/animations
COPY assets /app/assets
COPY server/server.gd server/gateway.py server/start_local.py /app/server/
# Never use host .godot imports. Import textures/fonts with the pinned Linux binary.
RUN rm -rf /app/.godot && godot --headless --editor --path /app --import --quit
ENV GODOT_BIN=/usr/local/bin/godot NET_DATA_DIR=/data/worlds NET_PORT=9081 PORT=9080 PYTHONUNBUFFERED=1
EXPOSE 9080
CMD ["python3", "server/start_local.py"]
