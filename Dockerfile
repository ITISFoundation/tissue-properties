# syntax=docker/dockerfile:1.7

# =============================================================================
# Stage: assets
# Lays out the static site (viewer + bundled CSV) under /site so it can be
# copied into the production runtime stage.
# =============================================================================
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc AS assets

WORKDIR /site

COPY index.html /site/index.html
COPY csv-to-html-table /site/csv-to-html-table

# =============================================================================
# Stage: production
# Serves the static site with static-web-server (Rust). Tiny runtime image,
# no shell required for the server itself.
# =============================================================================
FROM joseluisq/static-web-server:2-alpine@sha256:8aa4c9a140a76f18d154656503dbd856effd9d7cd75e6092348d522e73b3ca28 AS production

LABEL org.opencontainers.image.source="https://github.com/ITISFoundation/tissue-properties"
LABEL org.opencontainers.image.title="tissue-properties"
LABEL org.opencontainers.image.description="ITIS tissue properties database viewer for o²S²PARC"

# The base image runs as the unprivileged `sws` user; switch to root to install
# packages and stage files, then switch back at the end.
USER root

# tini + bash + curl give us a healthcheck and a robust entrypoint for output sync.
# coreutils is needed for `cp -L` / `install -D` semantics used by copy_outputs.sh.
# Versions pinned for the Alpine 3.22 base used by static-web-server:2-alpine.
RUN apk add --no-cache \
        bash=5.2.37-r0 \
        coreutils=9.7-r1 \
        curl=8.14.1-r2 \
        tini=0.19.0-r3

# Static site assets
COPY --from=assets /site /public

# Entrypoint scripts (all SWS settings come from env vars below)
COPY docker/copy_outputs.sh /usr/local/bin/copy_outputs.sh
COPY docker/entrypoint.sh /usr/local/bin/tissue-properties-entrypoint.sh
COPY docker/docker_healthcheck.bash /usr/local/bin/docker_healthcheck.bash
RUN chmod +x /usr/local/bin/copy_outputs.sh \
             /usr/local/bin/tissue-properties-entrypoint.sh \
             /usr/local/bin/docker_healthcheck.bash

# Defaults — overridable from compose / runtime.yml
ENV SERVER_ROOT=/public \
    SERVER_PORT=8080 \
    SERVER_HOST="::" \
    SERVER_LOG_LEVEL=info \
    SERVER_HEALTH=true \
    SERVER_COMPRESSION=true \
    SERVER_CACHE_CONTROL_HEADERS=true \
    DY_SIDECAR_PATH_OUTPUTS=/var/outputs \
    TISSUE_PROPERTIES_CSV=/public/csv-to-html-table/data/TissueProperties.csv

# Make sure the sidecar mount point exists and is owned by sws so the
# entrypoint can write to it without escalated privileges.
RUN mkdir -p "${DY_SIDECAR_PATH_OUTPUTS}" \
    && chown -R sws:sws "${DY_SIDECAR_PATH_OUTPUTS}" /public

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/docker_healthcheck.bash"]

USER sws
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/tissue-properties-entrypoint.sh"]

# =============================================================================
# Stage: development
# Vite dev server with hot module reload. Bind-mount csv-to-html-table/ from
# the host (see docker-compose-local.yml) to edit and see changes live.
# =============================================================================
FROM node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293 AS development

# Versions pinned for the Alpine 3.23 base used by node:20-alpine.
RUN apk add --no-cache \
        bash=5.3.3-r1 \
        tini=0.19.0-r3

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY index.html ./index.html
COPY csv-to-html-table ./csv-to-html-table
COPY vite.config.js ./vite.config.js

ENV HOST=0.0.0.0 \
    PORT=8080 \
    DY_SIDECAR_PATH_OUTPUTS=/var/outputs \
    TISSUE_PROPERTIES_CSV=/app/csv-to-html-table/data/TissueProperties.csv

EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--", "npm", "run"]
CMD ["dev"]
