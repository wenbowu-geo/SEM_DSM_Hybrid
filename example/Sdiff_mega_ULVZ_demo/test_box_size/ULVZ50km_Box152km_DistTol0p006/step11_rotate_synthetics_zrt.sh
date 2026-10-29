#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auxiliary/hydra_environment.sh" || exit 1
# Step 11: write station-aligned Z/R/T versions of the 1-D and 3-D synthetics.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"${PYTHON_BIN:-python3}" "${ROOT_DIR}/auxiliary/rotate_synthetics_zrt.py" "$@"
