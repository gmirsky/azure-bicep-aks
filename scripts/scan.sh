#!/usr/bin/env bash
set -euo pipefail

have_scanner=false

if command -v trivy >/dev/null 2>&1; then
  have_scanner=true
  echo "Running Trivy config scan..."
  trivy config --severity HIGH,CRITICAL .
fi

if command -v checkov >/dev/null 2>&1; then
  have_scanner=true
  echo "Running Checkov scan..."
  checkov -d . --framework bicep --config-file .checkov.yaml
fi

if [[ "$have_scanner" == false ]]; then
  echo "No vulnerability scanner found (trivy/checkov)."
  echo "Install one and rerun scripts/scan.sh"
  exit 2
fi
