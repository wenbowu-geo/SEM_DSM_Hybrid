#!/usr/bin/env bash
#
# Step 2: Explain which SPECFEM3D model implementation will be used.
# This script runs from its demo root.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"
SRC_PATH="${ROOT_DIR}/../../../src/SPECFEM3D/src/generate_databases/model_tomography.f90"
DEMO_SPECIFIC_PATH="${SRC_PATH}"

param() {
  local key=$1
  local default=${2:-}
  local value
  value=$(awk -F= -v key="$key" '
    $0 !~ /^[[:space:]]*#/ && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      print v
      found=1
      exit
    }
    END { if (!found) exit 1 }
  ' "${PARAM_FILE}" 2>/dev/null || true)
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default}"
  fi
}

DSM1D_OR_3D=$(param DSM1D_OR_3D DSM3D)
DSM1D_OR_3D=$(printf '%s' "${DSM1D_OR_3D}" | tr '[:lower:]' '[:upper:]')

cat <<EOF_HEADER
----------------------------------------------------------------------
Step 2: Model implementation
----------------------------------------------------------------------

Current model mode from DATA/Par_file_SEM_DSM:
  DSM1D_OR_3D = ${DSM1D_OR_3D}

EOF_HEADER

if [[ "${DSM1D_OR_3D}" == "DSM1D" ]]; then
cat <<EOF_DSM1D
DSM1D mode uses the 1-D DSM background model in SPECFEM3D.
CMB topography and heterogeneity tiles are not applied:
  - Step 1 writes MODEL=DSM1D
  - Step 1 generates a flat CMB interface
  - xgenerate_databases calls model_DSM1D, not model_DSM3D

This mode is useful for checking SEM-DSM consistency; the scattered
wavefield should be near zero for the 1-D background model.
----------------------------------------------------------------------
EOF_DSM1D
elif [[ "${DSM1D_OR_3D}" == "DSM3D" ]]; then
cat <<EOF_DSM3D
If you want to use your own 3-D model, modify the implementation in:
  ${SRC_PATH}

For this demo, the 3-D model implementation lives in:
  ${DEMO_SPECIFIC_PATH}

That file contains the model implementation used by xgenerate_databases.
After modifying the source code, you must recompile the SPECFEM3D code
before running Step 1 (creating the mesh and generating the databases).

The current implementation is already set up for this demo,
so this demo can move directly to the next step.
----------------------------------------------------------------------
EOF_DSM3D
else
cat <<EOF_ERROR
Error: DSM1D_OR_3D must be DSM1D or DSM3D, got '${DSM1D_OR_3D}'.
----------------------------------------------------------------------
EOF_ERROR
exit 1
fi
