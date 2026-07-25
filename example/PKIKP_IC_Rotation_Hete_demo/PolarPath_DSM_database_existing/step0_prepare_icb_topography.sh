#!/usr/bin/env bash
#
# Step 0: prepare generated DSM3D input files.
# In DSM3D mode this creates both ICB topography and heterogeneity tiles.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEM_DSM_PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"
TOPO_GENERATOR="${ROOT_DIR}/DATA/topo_files/generate_bump.py"
HETEROGENEITY_GENERATOR="${ROOT_DIR}/DATA/heterogeneities/generate_stochastic_heterogeneity_tiled_overlap.py"
TOPO_FILE="${ROOT_DIR}/DATA/topo_files/latlon_ICB_topo.txt"
DEFAULT_PYTHON="/user/wenbo.wu/.conda/envs/sqhao_seismo/bin/python"
if [[ -z "${PYTHON_BIN:-}" ]]; then
  if [[ -x "${DEFAULT_PYTHON}" ]]; then
    PYTHON_BIN="${DEFAULT_PYTHON}"
  else
    PYTHON_BIN=python3
  fi
fi

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
  ' "${SEM_DSM_PARAM_FILE}" 2>/dev/null || true)
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default}"
  fi
}

write_zero_icb_topography() {
  mkdir -p "$(dirname "${TOPO_FILE}")"
  cat > "${TOPO_FILE}" <<EOF_ZERO_TOPO
2 2
0.0 0.0 1.0 1.0
1.0 1.0
0.00 0.00
0.00 0.00
EOF_ZERO_TOPO
}

echo "----------------------------------------------------------------------"
echo "Step 0: Prepare DSM3D Inputs"
echo "----------------------------------------------------------------------"

DSM1D_OR_3D=$(param DSM1D_OR_3D DSM3D)
DSM1D_OR_3D=$(printf '%s' "${DSM1D_OR_3D}" | tr '[:lower:]' '[:upper:]')
case "${DSM1D_OR_3D}" in
  DSM1D|DSM3D) ;;
  *)
    echo "Error: DSM1D_OR_3D must be DSM1D or DSM3D, got '${DSM1D_OR_3D}'." >&2
    exit 1
    ;;
esac
echo "DSM1D_OR_3D=${DSM1D_OR_3D}"

if [[ "${DSM1D_OR_3D}" == "DSM1D" ]]; then
  echo "DSM1D selected: writing zero ICB topography."
  write_zero_icb_topography
  echo "Zero topography file:"
  echo "  ${TOPO_FILE}"
  echo "----------------------------------------------------------------------"
  exit 0
fi

if [[ ! -f "${TOPO_GENERATOR}" ]]; then
  echo "Error: ICB topography generator is missing:" >&2
  echo "  ${TOPO_GENERATOR}" >&2
  exit 1
fi

echo "Generating ICB topography with:"
echo "  ${TOPO_GENERATOR}"
(cd "$(dirname "${TOPO_GENERATOR}")" && "${PYTHON_BIN}" "$(basename "${TOPO_GENERATOR}")")

if [[ ! -f "${TOPO_FILE}" ]]; then
  echo "Error: topography generator did not create:" >&2
  echo "  ${TOPO_FILE}" >&2
  exit 1
fi

echo "ICB topography file:"
echo "  ${TOPO_FILE}"

if [[ ! -f "${HETEROGENEITY_GENERATOR}" ]]; then
  echo "Error: stochastic heterogeneity generator is missing:" >&2
  echo "  ${HETEROGENEITY_GENERATOR}" >&2
  exit 1
fi

echo "Generating stochastic heterogeneity tiles with:"
echo "  ${HETEROGENEITY_GENERATOR}"
(cd "$(dirname "${HETEROGENEITY_GENERATOR}")" && "${PYTHON_BIN}" "$(basename "${HETEROGENEITY_GENERATOR}")")

TOMOGRAPHY_PATH=$(param TOMOGRAPHY_PATH "DATA/heterogeneities/tiles")
if [[ "${TOMOGRAPHY_PATH}" != /* ]]; then
  TOMOGRAPHY_PATH="${ROOT_DIR}/${TOMOGRAPHY_PATH}"
fi
if ! compgen -G "${TOMOGRAPHY_PATH}/tomography_model_box*.xyz" >/dev/null; then
  echo "Error: heterogeneity generator did not create tomography_model_box*.xyz in:" >&2
  echo "  ${TOMOGRAPHY_PATH}" >&2
  exit 1
fi

echo "Heterogeneity tile directory:"
echo "  ${TOMOGRAPHY_PATH}"
echo "----------------------------------------------------------------------"
