#!/usr/bin/env bash
# Hydra OpenHPC environment used by this checkout.
if [[ -f /etc/profile.d/lmod.sh ]]; then
  source /etc/profile.d/lmod.sh || return 1
elif ! type module >/dev/null 2>&1; then
  echo "Error: Hydra Lmod initialization is unavailable (/etc/profile.d/lmod.sh)." >&2
  return 1
fi
module purge || return $?
module load gnu14/14.2.0 openmpi5/5.0.7 || return $?
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export PYTHONNOUSERSITE=1
export PYTHON_BIN=/user/wenbo.wu/.conda/envs/sqhao_seismo/bin/python
HYDRA_AUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${HYDRA_AUX_DIR}/hydra_python" ]]; then
  export PATH="${HYDRA_AUX_DIR}/hydra_python:${PATH}"
fi
export HYDRA_ENV_FILE="${HYDRA_AUX_DIR}/hydra_environment.sh"
