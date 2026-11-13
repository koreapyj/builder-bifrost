# syntax=docker/dockerfile:1
#
# Patched Bifrost gateway + Go plugins, built in one Go workspace.
#
# Build context: a Bifrost tree prepared by `make prepare` / CI (patches applied,
# plugins staged into .builder/ by support/plugins.sh). Build it through
# support/build-image.sh, which passes GO_VERSION from .builder/go-version.
#
# The runtime layout mirrors upstream's transports/Dockerfile (/app/main, the
# same entrypoint, APP_DIR=/app/data, UID 1000:0, port 8080), so the official
# Helm chart works with only the image changed. Plugins are at
# /app/plugins/<name>.so.
#
# Base is Debian (glibc) instead of upstream's Alpine: the host must be a
# dynamically linked cgo binary to load plugins, and glibc is the well-trodden
# path for Go's plugin package.

ARG GO_VERSION
ARG NODE_VERSION=24
ARG DEBIAN_SUITE=trixie

FROM node:${NODE_VERSION}-${DEBIAN_SUITE}-slim AS node

# --- Dashboard (same commands as upstream's ui-builder stage) ---------------
FROM node AS ui
ARG UI_BUILD_SCRIPT=build-enterprise
WORKDIR /app
COPY ui/package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY ui/ ./
RUN npm run "${UI_BUILD_SCRIPT}"

# --- Go: bifrost-http + plugins (Node is available for plugin pre-builds) ---
FROM golang:${GO_VERSION}-${DEBIAN_SUITE} AS builder
RUN apt-get update && \
    apt-get install -y --no-install-recommends libstdc++6 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    node --version && npm --version
WORKDIR /build
COPY . .
COPY --from=ui /app/out ./transports/bifrost-http/ui
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/.npm \
    bash .builder/build.sh /out

# --- Runtime ------------------------------------------------------------------
FROM debian:${DEBIAN_SUITE}-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Binaries stay root-owned and read-only for the runtime user.
COPY --from=builder /out/main /app/main
COPY --from=builder /out/plugins/ /app/plugins/
COPY --from=builder /build/transports/docker-entrypoint.sh /app/docker-entrypoint.sh

ARG ARG_APP_PORT=8080
ARG ARG_APP_HOST=0.0.0.0
ARG ARG_LOG_LEVEL=info
ARG ARG_LOG_STYLE=json
ARG ARG_APP_DIR=/app/data
ENV APP_PORT=$ARG_APP_PORT \
    APP_HOST=$ARG_APP_HOST \
    LOG_LEVEL=$ARG_LOG_LEVEL \
    LOG_STYLE=$ARG_LOG_STYLE \
    APP_DIR=$ARG_APP_DIR
ENV GOGC="" \
    GOMEMLIMIT=""

RUN mkdir -p "$APP_DIR/logs" && \
    useradd --uid 1000 --gid 0 --no-create-home --shell /bin/sh appuser && \
    chown -R 1000:0 "$APP_DIR" && \
    { [ "$APP_DIR" = "/app" ] || chmod -R g=rwX "$APP_DIR"; } && \
    chmod 0755 /app/main /app/docker-entrypoint.sh && \
    find /app/plugins -type f -exec chmod 0644 {} +

USER 1000:0
VOLUME ["${APP_DIR}"]
EXPOSE $APP_PORT

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:${APP_PORT}/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["/app/main"]
