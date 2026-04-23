#!/usr/bin/env bash
# Container HEALTHCHECK: SWS exposes a /health endpoint when SERVER_HEALTH=true.
set -euo pipefail
curl --fail --silent --show-error --max-time 4 \
    "http://127.0.0.1:${SERVER_PORT:-8080}/health" >/dev/null
