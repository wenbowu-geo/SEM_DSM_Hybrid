#!/usr/bin/env bash
# Step 6: Check and reuse the existing final 1-D synthetics.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -gt 0 ]]; then
    echo "Usage: $0 (checks existing synthetics; no DSM or recombination)" >&2
    exit 2
fi
exec "${PYTHON_BIN:-python3}" "${ROOT_DIR}/auxiliary/check_existing_1d_synthetics.py"
