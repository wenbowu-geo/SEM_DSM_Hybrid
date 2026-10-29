#!/usr/bin/env bash
# Refresh source amplitudes using the configured existing DSM traces.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${1:-}" == "--synthesis-only" ]]; then
    cd "${ROOT_DIR}"
    exec "${PYTHON_BIN:-python3}" auxiliary/synthesize_cmtsolution_sac.py \
        --sem-par-file DATA/Par_file_SEM_DSM --clean
fi
echo "This case reuses DSM traces. Run: bash $0 --synthesis-only" >&2
exit 1
