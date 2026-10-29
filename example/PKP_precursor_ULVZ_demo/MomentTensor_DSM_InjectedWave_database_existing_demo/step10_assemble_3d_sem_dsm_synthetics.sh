#!/usr/bin/env bash
#
# Step 10: assemble final 3-D SEM-DSM synthetics from this case's SEM
# coupling output and the existing DSM database configured in Par_file_SEM_DSM.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARAM_FILE="${ROOT_DIR}/DATA/Par_file_SEM_DSM"
PYTHON_BIN="${PYTHON_BIN:-python3}"

param() {
  local key=$1 fallback=${2:-}
  awk -F= -v key="$key" -v fallback="$fallback" '
    $0 !~ /^[[:space:]]*#/ && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      print v
      found=1
      exit
    }
    END { if (!found) print fallback }
  ' "${PARAM_FILE}"
}

resolve_case_path() {
  local path=$1
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${ROOT_DIR}/${path}"
  fi
}

DSM_DATABASE_DIR_RAW=$(param DSM_DATABASE_DIR "")
INJECTED_METADATA_RAW=$(param INJECTED_WAVES_METADATA "")

if [[ -z "${DSM_DATABASE_DIR_RAW}" ]]; then
  echo "Error: set DSM_DATABASE_DIR in ${PARAM_FILE}."
  exit 1
fi
if [[ -z "${INJECTED_METADATA_RAW}" ]]; then
  echo "Error: set INJECTED_WAVES_METADATA in ${PARAM_FILE}."
  exit 1
fi

DSM_DATABASE_DIR=$(resolve_case_path "${DSM_DATABASE_DIR_RAW}")
INJECTED_METADATA=$(resolve_case_path "${INJECTED_METADATA_RAW}")
# Match the wavefield directory selected by Step 8, including reused injection.
INJECTION_OUTPUT=$(param INJECTED_WAVEFIELD_PATH "WORK/InjectedWaves/OUTPUT_FILES")
if [[ "${INJECTION_OUTPUT}" != /* ]]; then
  INJECTION_OUTPUT="${ROOT_DIR}/${INJECTION_OUTPUT}"
fi
GREEN_METADATA="${INJECTION_OUTPUT%/}/InjectedWaves_Par_file"
if [[ ! -f "${GREEN_METADATA}" ]]; then
  echo "Error: actual injected-wavefield timing metadata not found: ${GREEN_METADATA}" >&2
  exit 1
fi

SOURCE_MODE=$(param SINGLE_FORCE_ENZ -1)
# Reuse final synthetics only when their source, receivers and provenance match.
ONE_D_DIR=$("${PYTHON_BIN}" "${ROOT_DIR}/auxiliary/check_existing_1d_synthetics.py" --print-path)
ONE_D_DSM_MODEL=""
ONE_D_SCALE="none"

echo "----------------------------------------------------------------------"
echo "Starting Step 10: Assemble 3-D SEM-DSM synthetics"
echo "Root Directory: ${ROOT_DIR}"
echo "SINGLE_FORCE_ENZ=${SOURCE_MODE}"
echo "1-D DSM SAC directory: ${ONE_D_DIR}"
echo "InjectedWaves metadata: ${INJECTED_METADATA}"
echo "----------------------------------------------------------------------"

cd "${ROOT_DIR}"
HELPER="auxiliary/assemble_3d_sem_dsm_synthetics.py"
args=(
  "${HELPER}"
  --green-metadata "${GREEN_METADATA}"
  --one-d-dir "${ONE_D_DIR}"
  --coupling-dir "${ROOT_DIR}/WORK/Coupling/OUTPUT_FILES"
  --metadata "${INJECTED_METADATA}"
  --stations "${ROOT_DIR}/DATA/tele_station.txt"
  --cmt "${ROOT_DIR}/DATA/CMTSOLUTION"
  --output-root "${ROOT_DIR}/OUTPUT_FILES"
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
