#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting executable bit for .sh files in: ${SCRIPT_DIR}"
chmod +x "${SCRIPT_DIR}"/*.sh
echo "Done."
