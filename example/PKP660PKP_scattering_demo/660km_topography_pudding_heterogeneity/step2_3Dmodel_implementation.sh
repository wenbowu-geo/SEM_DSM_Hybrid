#!/usr/bin/env bash
#
# Step 2: Explain which SPECFEM3D model implementation will be used.
# This script runs from its demo root.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"
GEN_SRC_DIR="${ROOT_DIR}/../../../src/SPECFEM3D/src/generate_databases"
SRC_PATH="${GEN_SRC_DIR}/model_tomography.f90"
GET_MODEL_PATH="${GEN_SRC_DIR}/get_model.F90"
DEMO_MODEL_DIR="${GEN_SRC_DIR}/model_tomo/660km_basalt_heterogeneity/660km_topography_pudding_heterogeneity"
DEMO_SPECIFIC_PATH="${DEMO_MODEL_DIR}/model_tomography.f90"

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
ICB topography and heterogeneity tiles are not applied:
  - Step 1 writes MODEL=DSM1D
  - Step 1 generates a flat ICB interface
  - xgenerate_databases calls model_DSM1D, not model_DSM3D

This mode is useful for checking SEM-DSM consistency; the scattered
wavefield should be near zero for the 1-D background model.
----------------------------------------------------------------------
EOF_DSM1D
elif [[ "${DSM1D_OR_3D}" == "DSM3D" ]]; then
cat <<EOF_DSM3D
This demo uses the case-specific 660 km pudding/topography implementation in:
  ${DEMO_MODEL_DIR}

Step 2 installs these files into the active xgenerate_databases source files:
  ${GET_MODEL_PATH}
  ${SRC_PATH}

After Step 2, rebuild xgenerate_databases before Step 3 if the binary has not
already been rebuilt with this source.
----------------------------------------------------------------------
EOF_DSM3D
if [[ ! -f "${DEMO_MODEL_DIR}/get_model.F90" || ! -f "${DEMO_MODEL_DIR}/model_tomography.f90" ]]; then
  echo "Error: missing case-specific model source in ${DEMO_MODEL_DIR}." >&2
  exit 1
fi
cp "${DEMO_MODEL_DIR}/get_model.F90" "${GET_MODEL_PATH}"
cp "${DEMO_MODEL_DIR}/model_tomography.f90" "${SRC_PATH}"
echo "Installed case-specific 660 km model source into ${GEN_SRC_DIR}."
else
cat <<EOF_ERROR
Error: DSM1D_OR_3D must be DSM1D or DSM3D, got '${DSM1D_OR_3D}'.
----------------------------------------------------------------------
EOF_ERROR
exit 1
fi
