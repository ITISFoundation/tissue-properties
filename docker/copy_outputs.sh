#!/usr/bin/env bash
# Copy the bundled TissueProperties.csv into the dynamic-sidecar's outputs
# directory so it gets uploaded as `output_1` (see .osparc/.../metadata.yml).
#
# This replaces the old simcore-sdk based input-retriever.py — modern dynamic
# services rely on the sidecar to sync DY_SIDECAR_PATH_OUTPUTS to platform
# storage, so we just need to drop the file in the right place.

set -euo pipefail

: "${TISSUE_PROPERTIES_CSV:?TISSUE_PROPERTIES_CSV must be set}"
: "${DY_SIDECAR_PATH_OUTPUTS:?DY_SIDECAR_PATH_OUTPUTS must be set}"

if [[ ! -f "${TISSUE_PROPERTIES_CSV}" ]]; then
    echo "[copy_outputs] source CSV not found: ${TISSUE_PROPERTIES_CSV}" >&2
    exit 1
fi

dest_dir="${DY_SIDECAR_PATH_OUTPUTS}/output_1"
dest_file="${dest_dir}/TissueProperties.csv"

mkdir -p "${dest_dir}"
cp -f "${TISSUE_PROPERTIES_CSV}" "${dest_file}"
echo "[copy_outputs] published ${dest_file}"
