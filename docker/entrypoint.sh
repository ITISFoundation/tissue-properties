#!/usr/bin/env bash
# Container entrypoint:
#   1. populate the sidecar outputs directory with TissueProperties.csv,
#   2. exec static-web-server to serve the viewer.

set -euo pipefail

if [[ -z "${DY_SIDECAR_PATH_OUTPUTS:-}" ]]; then
    echo "[entrypoint] FATAL: DY_SIDECAR_PATH_OUTPUTS is not set." >&2
    echo "[entrypoint] This variable must be injected by the dynamic-sidecar." >&2
    exit 1
fi

/usr/local/bin/copy_outputs.sh

exec static-web-server "$@"
