#!/usr/bin/env bash
#
# Step 0: Stage the old 660 km pudding heterogeneity model for xgenerate_databases.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OLD_HETERO_DIR="/proj/mazu/wenbowu/SEM_DSM/SPECFEM3D_old/EXAMPLES_COUPLING/PKPPKPbc_660_PudingAlldepth_20180824CI/DATA/meshfem3D_files/heterogeneities"
HETERO_DIR="${ROOT_DIR}/DATA/heterogeneities"

echo "----------------------------------------------------------------------"
echo "Starting Step 0: 660 km pudding heterogeneity preparation"
echo "Root Directory:         ${ROOT_DIR}"
echo "Old heterogeneity dir:  ${OLD_HETERO_DIR}"
echo "Case heterogeneity dir: ${HETERO_DIR}"
echo "----------------------------------------------------------------------"

mkdir -p "${HETERO_DIR}"

for file in Puding_heterogeneities.py exp_ACF_heterogeneities.py submit_puding.cmd Puding_model.png; do
  if [[ -f "${OLD_HETERO_DIR}/${file}" ]]; then
    cp "${OLD_HETERO_DIR}/${file}" "${HETERO_DIR}/${file}"
  fi
done

if [[ "${REGENERATE_PUDING_HETEROGENEITY:-0}" == "1" ]]; then
  if [[ -f "${HETERO_DIR}/tomography_model.xyz" && ! -L "${HETERO_DIR}/tomography_model.xyz" ]]; then
    echo "Refusing to overwrite existing real file: ${HETERO_DIR}/tomography_model.xyz" >&2
    echo "Move it aside first, or use the saved old-version model." >&2
    exit 1
  fi
  rm -f "${HETERO_DIR}/tomography_model.xyz"
  (
    cd "${HETERO_DIR}"
    python3 Puding_heterogeneities.py
  )
else
  if [[ ! -f "${OLD_HETERO_DIR}/tomography_model.xyz" ]]; then
    echo "Missing saved old-version tomography model: ${OLD_HETERO_DIR}/tomography_model.xyz" >&2
    exit 1
  fi
  if [[ ! -e "${HETERO_DIR}/tomography_model.xyz" ]]; then
    ln -s "${OLD_HETERO_DIR}/tomography_model.xyz" "${HETERO_DIR}/tomography_model.xyz"
  fi
fi

if [[ ! -f "${HETERO_DIR}/tomography_model.xyz" ]]; then
  echo "Missing ${HETERO_DIR}/tomography_model.xyz" >&2
  exit 1
fi

echo "----------------------------------------------------------------------"
echo "Preparation Summary:"
echo "  TOMOGRAPHY_PATH=${HETERO_DIR}"
echo "  tomography_model.xyz=$(readlink -f "${HETERO_DIR}/tomography_model.xyz")"
echo "Step 0: Heterogeneity preparation complete. Move to Step 1."
echo "----------------------------------------------------------------------"
