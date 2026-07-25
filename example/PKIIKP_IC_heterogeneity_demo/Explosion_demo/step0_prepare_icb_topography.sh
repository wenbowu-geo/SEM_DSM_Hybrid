#!/usr/bin/env bash
#
# Step 0: generate Python-prepared ICB topography and inner-core heterogeneity inputs.

set -euo pipefail
shopt -s nullglob

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEM_DSM_PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"

if [[ -z "${PYTHON_BIN:-}" ]]; then
  if [[ -x "/user/wenbo.wu/.conda/envs/sqhao_seismo/bin/python" ]]; then
    PYTHON_BIN="/user/wenbo.wu/.conda/envs/sqhao_seismo/bin/python"
  else
    PYTHON_BIN="python3"
  fi
fi

TOPO_DIR="${ROOT_DIR}/DATA/topo_files"
TOPO_GENERATOR="${TOPO_DIR}/generate_bump.py"
TOPO_FILE="${TOPO_DIR}/latlon_ICB_topo.txt"

HETERO_DIR="${ROOT_DIR}/DATA/heterogeneities"
HETERO_GENERATOR="${HETERO_DIR}/generate_stochastic_heterogeneity_tiled_overlap.py"
TILE_DIR="${HETERO_DIR}/tiles"

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
    printf '%s
' "${value}"
  else
    printf '%s
' "${default}"
  fi
}

write_zero_icb_topography() {
  cat > "${TOPO_FILE}" <<EOF_ZERO_TOPO
2 2
0.0 0.0 1.0 1.0
1.0 1.0
0.00 0.00
0.00 0.00
EOF_ZERO_TOPO
}

warn_short_dsm_length() {
  local key=$1
  local value
  value=$(param "${key}" "")
  if [[ -z "${value}" ]]; then
    return
  fi

  if awk -v value="${value}" "BEGIN {
      if (value !~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eEdD][+-]?[0-9]+)?$/) exit 1
      exit !(value + 0 < 4000.0)
    }"; then
    echo "WARNING: ${key}=${value} s is shorter than 4000 s."
    echo "         Low-frequency PKIIKP DSM errors could be large due to wrap-around artifacts."
  fi
}

echo "----------------------------------------------------------------------"
echo "Step 0: Generate ICB Topography and Inner-Core Heterogeneity"
echo "----------------------------------------------------------------------"
echo "Using Python: ${PYTHON_BIN}"
echo ""

warn_short_dsm_length TIME_LENGTH_DSM_SOURCE_TO_BOX
warn_short_dsm_length TIME_LENGTH_DSM_BOX_TO_RECEIVER
warn_short_dsm_length TIME_LENGTH_DSM_1D
echo ""

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
  echo "DSM1D selected: writing zero ICB topography and skipping 3-D heterogeneity generation."
  mkdir -p "${TOPO_DIR}" "${TILE_DIR}"
  write_zero_icb_topography
  rm -f "${TILE_DIR}"/tomography_model_box*.xyz "${TILE_DIR}"/tomography_model_box*.vtk

  echo ""
  echo "Generated zero topography file:"
  echo "  ${TOPO_FILE}"
  echo "Skipped heterogeneity tiles:"
  echo "  ${TILE_DIR}"
  echo "----------------------------------------------------------------------"
  exit 0
fi

for required_file in "${TOPO_GENERATOR}" "${HETERO_GENERATOR}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Error: required generator is missing: ${required_file}" >&2
    exit 1
  fi
done

echo "Generating ICB topography..."
(cd "${TOPO_DIR}" && "${PYTHON_BIN}" "$(basename "${TOPO_GENERATOR}")")

if [[ ! -s "${TOPO_FILE}" ]]; then
  echo "Error: topography file was not generated: ${TOPO_FILE}" >&2
  exit 1
fi

echo ""
echo "Generating inner-core heterogeneity tiles..."
mkdir -p "${TILE_DIR}"
rm -f "${TILE_DIR}"/tomography_model_box*.xyz "${TILE_DIR}"/tomography_model_box*.vtk
(cd "${HETERO_DIR}" && "${PYTHON_BIN}" "$(basename "${HETERO_GENERATOR}")")

tiles=("${TILE_DIR}"/tomography_model_box*.xyz)
if [[ ${#tiles[@]} -eq 0 ]]; then
  echo "Error: no heterogeneity XYZ tiles were generated in ${TILE_DIR}" >&2
  exit 1
fi

echo ""
echo "Generated topography file:"
echo "  ${TOPO_FILE}"
echo "Generated heterogeneity tiles:"
echo "  ${TILE_DIR}"
echo "----------------------------------------------------------------------"
