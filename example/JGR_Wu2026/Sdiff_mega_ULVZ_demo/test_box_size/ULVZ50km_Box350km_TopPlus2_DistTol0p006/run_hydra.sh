#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auxiliary/hydra_environment.sh" || exit 1
python3 "${ROOT_DIR}/auxiliary/hydra_workflow.py" "${@:-status}"
