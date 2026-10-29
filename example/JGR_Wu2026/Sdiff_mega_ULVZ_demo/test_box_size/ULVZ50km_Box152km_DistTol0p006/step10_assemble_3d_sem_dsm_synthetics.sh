#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auxiliary/hydra_environment.sh" || exit 1
#
# Step 10: assemble final 3-D SEM-DSM synthetics.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"

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

echo "----------------------------------------------------------------------"
echo "Starting Step 10: Assemble 3-D SEM-DSM synthetics"
echo "Root Directory: ${ROOT_DIR}"
echo "----------------------------------------------------------------------"

SOURCE_MODE=$(param SINGLE_FORCE_ENZ -1)
ONE_D_ROOT=$(param DSM_1D_SYNTHETICS_DIR "WORK/DSM/1D_tele_syn")
if [[ "${ONE_D_ROOT}" != /* ]]; then
  ONE_D_ROOT="${ROOT_DIR}/${ONE_D_ROOT}"
fi
case "${SOURCE_MODE}" in
  -1)
    # Refresh this case's 1-D source combination using reusable DSM traces.
    (cd "${ROOT_DIR}" && "${PYTHON_BIN:-python3}" auxiliary/synthesize_cmtsolution_sac.py \
        --sem-par-file DATA/Par_file_SEM_DSM --if-needed --clean)
    ONE_D_DIR="${ROOT_DIR}/WORK/DSM/1D_tele_syn/OUTPUT_FILES/CMTSOLUTION_time_sac"
    ONE_D_DSM_MODEL=""
    ONE_D_SCALE="none"
    ;;
  0)
    # Ensure the combination belongs to this case's current source.
    (cd "${ROOT_DIR}" && python3 auxiliary/synthesize_cmtsolution_sac.py \
        --sem-par-file DATA/Par_file_SEM_DSM --if-needed --clean)
    ONE_D_DIR="${ROOT_DIR}/WORK/DSM/1D_tele_syn/OUTPUT_FILES/CMTSOLUTION_time_sac"
    ONE_D_DSM_MODEL=""
    ONE_D_SCALE="none"
    ;;
  1)
    ONE_D_DIR="${ONE_D_ROOT}/Fr/OUTPUT_FILES/disp_solid_time_sac"
    ONE_D_DSM_MODEL=""
    ONE_D_SCALE="none"
    ;;
  2)
    ONE_D_DIR="${ONE_D_ROOT}/Ft/OUTPUT_FILES/disp_solid_time_sac"
    ONE_D_DSM_MODEL=""
    ONE_D_SCALE="none"
    ;;
  3)
    ONE_D_DIR="${ONE_D_ROOT}/Fz/OUTPUT_FILES/disp_solid_time_sac"
    ONE_D_DSM_MODEL=""
    ONE_D_SCALE="none"
    ;;
  *)
    echo "Error: Unsupported SINGLE_FORCE_ENZ=${SOURCE_MODE}." >&2
    echo "Supported values: -1 explosion, 0 moment-tensor Green's functions, 1 North, 2 East, 3 Vertical." >&2
    exit 1
    ;;
esac

echo "SINGLE_FORCE_ENZ=${SOURCE_MODE}"
echo "1-D DSM SAC directory: ${ONE_D_DIR}"

cd "${ROOT_DIR}"
HELPER="auxiliary/assemble_3d_sem_dsm_synthetics.py"
args=(
  "${HELPER}"
  --one-d-dir "${ONE_D_DIR}"
)
if grep -q -- '--one-d-scale' "${HELPER}"; then
  args+=(--one-d-scale "${ONE_D_SCALE}")
fi
if [[ -n "${ONE_D_DSM_MODEL}" ]] && grep -q -- '--one-d-dsm-model' "${HELPER}"; then
  args+=(--one-d-dsm-model "${ONE_D_DSM_MODEL}")
fi
"${PYTHON_BIN}" "${args[@]}"

echo "----------------------------------------------------------------------"
echo "Step 10 complete."
echo "----------------------------------------------------------------------"
