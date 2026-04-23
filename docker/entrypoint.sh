#!/usr/bin/env bash
# Container entrypoint:
#   1. reconcile permissions on the sidecar-mounted outputs directory so the
#      unprivileged runtime user (`sws`) can write to it,
#   2. populate that directory with TissueProperties.csv,
#   3. exec static-web-server to serve the viewer (as `sws`).
#
# When this image runs under the o²S²PARC dynamic-sidecar, ${DY_SIDECAR_PATH_OUTPUTS}
# is bind-mounted from the host with the sidecar's UID/GID. The container's
# `sws` user has a fixed UID that almost never matches, so without this fixup
# we get EACCES when copy_outputs.sh tries to write the CSV.
#
# Pattern adapted from
# https://github.com/ITISFoundation/jupyter-math/blob/main/docker/entrypoint.bash

set -euo pipefail

INFO="[entrypoint]"
RUN_USER="sws"

echo "${INFO} starting container as $(id)"

if [[ ! -d "${DY_SIDECAR_PATH_OUTPUTS}" ]]; then
    echo "${INFO} FATAL: '${DY_SIDECAR_PATH_OUTPUTS}' is not mounted." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Align the runtime user with the host-owned outputs mount.
# ---------------------------------------------------------------------------
HOST_USERID=$(stat -c %u "${DY_SIDECAR_PATH_OUTPUTS}")
HOST_GROUPID=$(stat -c %g "${DY_SIDECAR_PATH_OUTPUTS}")
CONTAINER_USERID=$(id -u "${RUN_USER}")
CONTAINER_GROUPID=$(id -g "${RUN_USER}")

echo "${INFO} outputs dir owned by ${HOST_USERID}:${HOST_GROUPID}; ${RUN_USER} is ${CONTAINER_USERID}:${CONTAINER_GROUPID}"

if [[ "$(id -u)" -eq 0 ]]; then
    if [[ "${HOST_USERID}" -eq 0 ]]; then
        # Mount is root-owned (typical local `docker run` without sidecar):
        # just hand ownership to sws so it can write.
        echo "${INFO} mount is root-owned; chowning to ${RUN_USER}"
        chown -R "${RUN_USER}:${RUN_USER}" "${DY_SIDECAR_PATH_OUTPUTS}"
    elif [[ "${HOST_USERID}" -ne "${CONTAINER_USERID}" ]]; then
        # Mount is owned by an arbitrary host UID (the dynamic-sidecar's).
        # Add sws to the host group so files we create are readable back by
        # the sidecar, then take ownership of the directory so sws can
        # actually write into it. The sidecar runs as root on the host side
        # and reads via the bind-mount, so changing UID on the container
        # side does not lock it out.
        existing_group=$(getent group "${HOST_GROUPID}" | cut -d: -f1 || true)
        if [[ -z "${existing_group}" ]]; then
            existing_group="hostgrp"
            echo "${INFO} creating group ${existing_group} (gid=${HOST_GROUPID})"
            addgroup -g "${HOST_GROUPID}" "${existing_group}"
        fi
        echo "${INFO} adding ${RUN_USER} to group ${existing_group} (gid=${HOST_GROUPID})"
        addgroup "${RUN_USER}" "${existing_group}" || true

        echo "${INFO} chowning ${DY_SIDECAR_PATH_OUTPUTS} to ${RUN_USER}:${existing_group}"
        chown -R "${RUN_USER}:${existing_group}" "${DY_SIDECAR_PATH_OUTPUTS}"
        chmod -R u+rwX,g+rwX "${DY_SIDECAR_PATH_OUTPUTS}"
    fi

    TISSUE_PROPERTIES_CSV="${TISSUE_PROPERTIES_CSV:-}" \
    DY_SIDECAR_PATH_OUTPUTS="${DY_SIDECAR_PATH_OUTPUTS}" \
        su-exec "${RUN_USER}" /usr/local/bin/copy_outputs.sh

    echo "${INFO} dropping to ${RUN_USER} and exec'ing static-web-server"
    exec su-exec "${RUN_USER}" static-web-server "$@"
fi

# Already non-root (e.g. invoked manually); just try to proceed.
echo "${INFO} not running as root; skipping permission reconciliation"
/usr/local/bin/copy_outputs.sh
exec static-web-server "$@"
