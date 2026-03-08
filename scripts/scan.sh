#!/usr/bin/env bash
set -euo pipefail

# Track whether at least one supported scanner is available.
have_scanner=false

# Run Trivy misconfiguration scan when installed.
if command -v trivy >/dev/null 2>&1; then
  have_scanner=true
  echo "Running Trivy config scan..."
  trivy config --severity HIGH,CRITICAL .
fi

# Run Checkov with repository baseline config when installed.
if command -v checkov >/dev/null 2>&1; then
  have_scanner=true
  echo "Running Checkov scan..."
  checkov -d . --framework bicep --config-file .checkov.yaml
fi

# Fail with a clear message if no scanner binary is present.
if [[ "$have_scanner" == false ]]; then
  echo "No vulnerability scanner found (trivy/checkov)."
  echo "Install one and rerun scripts/scan.sh"
  exit 2
fi
