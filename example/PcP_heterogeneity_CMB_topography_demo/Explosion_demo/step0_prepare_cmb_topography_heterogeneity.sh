#!/usr/bin/env bash
#
# Step 0: generate the CMB topography and volumetric heterogeneity inputs.

set -euo pipefail
shopt -s nullglob

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOPO_GENERATOR="${ROOT_DIR}/DATA/topo_files/generate_bump.py"
HET_GENERATOR="${ROOT_DIR}/DATA/heterogeneities/generate_stochastic_heterogeneity_tiled_overlap.py"
TOPO_FILE="${ROOT_DIR}/DATA/topo_files/latlon_CMB_topo.txt"
HET_DIR="${ROOT_DIR}/DATA/heterogeneities/tiles"
SEM_DSM_PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"
DEFAULT_PYTHON="/user/wenbo.wu/.conda/envs/sqhao_seismo/bin/python"
if [[ -x "${DEFAULT_PYTHON}" ]]; then
  PYTHON="${PYTHON:-${DEFAULT_PYTHON}}"
else
  PYTHON="${PYTHON:-python3}"
fi

echo "----------------------------------------------------------------------"
echo "Step 0: Prepare CMB Topography and Heterogeneities"
echo "----------------------------------------------------------------------"
echo "Topography generator:"
echo "  ${TOPO_GENERATOR}"
echo "Heterogeneity generator:"
echo "  ${HET_GENERATOR}"
echo ""
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
  echo "DSM1D selected: skipping CMB topography and 3-D heterogeneity generation."
  echo "Step 1 will use MODEL=DSM1D and generate a flat CMB interface."
  echo "----------------------------------------------------------------------"
  exit 0
fi


echo "Generating CMB topography..."
(cd "${ROOT_DIR}/DATA/topo_files" && "${PYTHON}" generate_bump.py)
echo ""
echo "Generating volumetric heterogeneity tiles..."
(cd "${ROOT_DIR}/DATA/heterogeneities" && "${PYTHON}" generate_stochastic_heterogeneity_tiled_overlap.py)
echo ""
echo "Generated topography file:"
echo "  ${TOPO_FILE}"
echo "Generated heterogeneity tile directory:"
echo "  ${HET_DIR}"
echo ""
if [[ -f "${TOPO_FILE}" ]]; then
  echo "CMB topography file exists."
else
  echo "Error: CMB topography file is missing after generation." >&2
  exit 1
fi
if compgen -G "${HET_DIR}/tomography_model_box*.xyz" >/dev/null; then
  echo "Heterogeneity tiles exist."
else
  echo "Error: no tomography_model_box*.xyz files were generated in ${HET_DIR}." >&2
  exit 1
fi
echo "----------------------------------------------------------------------"
