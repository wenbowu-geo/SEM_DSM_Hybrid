#!/usr/bin/env bash
#
# Step 0: prepare ICB topography and heterogeneity inputs for DSM3D.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Case-specific SPECFEM3D model installation ---
REPO_ROOT="$(cd "${ROOT_DIR}/../../.." && pwd)"
SPECFEM_ROOT="${REPO_ROOT}/src/SPECFEM3D"
MODEL_SETUP_HELPER="${ROOT_DIR}/auxiliary/select_generate_databases_model.sh"

if [[ ! -f "${MODEL_SETUP_HELPER}" ]]; then
  echo "Error: model-selection helper is missing: ${MODEL_SETUP_HELPER}" >&2
  exit 1
fi

DSM_MODEL_MODE=$(awk -F= '
  $0 !~ /^[[:space:]]*#/ && $1 ~ /^[[:space:]]*DSM1D_OR_3D[[:space:]]*$/ {
    value=$2
    sub(/#.*/, "", value)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    print toupper(value)
    found=1
    exit
  }
  END { if (!found) print "DSM3D" }
' "${ROOT_DIR}/DATA/Par_file_SEM_DSM")

# shellcheck source=auxiliary/select_generate_databases_model.sh
source "${MODEL_SETUP_HELPER}"
select_generate_databases_model "${ROOT_DIR}" "${SPECFEM_ROOT}" "${DSM_MODEL_MODE}"

model_usage() {
  echo "Usage: $0 [--check|--install|--install-only]"
}

require_case_model_sources() {
  local source_file
  for source_file in "${CASE_MODEL}" "${CASE_GET_MODEL}" "${CASE_SAVE_DEPTH}"; do
    if [[ ! -f "${source_file}" ]]; then
      echo "Error: required case model source is missing: ${source_file}" >&2
      return 1
    fi
  done
}

build_case_generator() {
  (
    backup_dir=$(mktemp -d)
    cleanup_case_sources() {
      status=$?
      trap - EXIT HUP INT TERM
      cp -p "${backup_dir}/model_tomography.f90" "${ACTIVE_MODEL}"
      cp -p "${backup_dir}/get_model.F90" "${ACTIVE_GET_MODEL}"
      cp -p "${backup_dir}/save_depth_id.f90" "${ACTIVE_SAVE_DEPTH}"
      rm -rf "${backup_dir}"
      echo "Restored all original shared generate_databases Fortran sources."
      exit "${status}"
    }
    trap cleanup_case_sources EXIT HUP INT TERM

    cp -p "${ACTIVE_MODEL}" "${backup_dir}/model_tomography.f90"
    cp -p "${ACTIVE_GET_MODEL}" "${backup_dir}/get_model.F90"
    cp -p "${ACTIVE_SAVE_DEPTH}" "${backup_dir}/save_depth_id.f90"
    cp "${CASE_MODEL}" "${ACTIVE_MODEL}"
    cp "${CASE_GET_MODEL}" "${ACTIVE_GET_MODEL}"
    cp "${CASE_SAVE_DEPTH}" "${ACTIVE_SAVE_DEPTH}"
    echo "Temporarily installed this case's three Fortran sources for compilation."

    make -C "${SPECFEM_ROOT}" CLEAN=generate_databases clean
    make -C "${SPECFEM_ROOT}" xgenerate_databases
  )
}

check_case_model() {
  require_case_model_sources
  if [[ ! -x "${GENERATOR}" || "${CASE_MODEL}" -nt "${GENERATOR}" || \
        "${CASE_GET_MODEL}" -nt "${GENERATOR}" || \
        "${CASE_SAVE_DEPTH}" -nt "${GENERATOR}" ]]; then
    echo "Error: xgenerate_databases is missing or older than the case sources." >&2
    echo "Run '$0 --install' to rebuild it." >&2
    return 1
  fi
}

ensure_case_model() {
  require_case_model_sources
  build_case_generator
  check_case_model
  echo "Case-specific xgenerate_databases is ready; shared sources were restored."
}

if [[ $# -gt 1 ]]; then
  model_usage >&2
  exit 2
fi

MODEL_SETUP_MODE="${1:-}"
case "${MODEL_SETUP_MODE}" in
  "")
    ensure_case_model
    ;;
  --check)
    check_case_model
    echo "Case-specific xgenerate_databases is ready; shared sources remain unchanged."
    exit 0
    ;;
  --install)
    require_case_model_sources
    build_case_generator
    check_case_model
    echo "Case-specific xgenerate_databases is ready; shared sources were restored."
    ;;
  --install-only)
    require_case_model_sources
    build_case_generator
    check_case_model
    echo "Case-specific xgenerate_databases is ready; shared sources were restored."
    exit 0
    ;;
  *)
    model_usage >&2
    exit 2
    ;;
esac
# --- End case-specific SPECFEM3D model installation ---

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
