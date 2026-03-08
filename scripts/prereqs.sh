#!/usr/bin/env bash
set -euo pipefail

# Ensure required CLIs are present before doing any Azure operations.
if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI is required. Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse Azure CLI output."
  exit 1
fi

# Optional subscription argument lets callers target a non-default subscription.
SUBSCRIPTION_ID="${1:-}"

if [[ -n "$SUBSCRIPTION_ID" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Print the effective subscription for traceability in CI/local runs.
CURRENT_SUBSCRIPTION="$(az account show --query id -o tsv)"
echo "Using subscription: $CURRENT_SUBSCRIPTION"

# Register required resource providers if not already registered.
providers=(
  Microsoft.ContainerService
  Microsoft.Network
  Microsoft.ContainerRegistry
  Microsoft.KeyVault
  Microsoft.OperationalInsights
  Microsoft.Monitor
  Microsoft.Dashboard
)

for provider in "${providers[@]}"; do
  state="$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || true)"
  if [[ "$state" != "Registered" ]]; then
    echo "Registering provider: $provider"
    az provider register --namespace "$provider" --wait >/dev/null
  else
    echo "Provider already registered: $provider"
  fi
done

# Register AKS features used by this template.
features=(
  Microsoft.ContainerService/AKS-AzureKeyVaultSecretsProvider
  Microsoft.ContainerService/EnableOIDCIssuerPreview
)

for feature in "${features[@]}"; do
  namespace="${feature%%/*}"
  feature_name="${feature##*/}"

  feature_state="$(az feature show --namespace "$namespace" --name "$feature_name" --query properties.state -o tsv 2>/dev/null || true)"

  if [[ "$feature_state" == "Registered" ]]; then
    echo "Feature already registered: $feature"
    continue
  fi

  echo "Registering feature: $feature"
  az feature register --namespace "$namespace" --name "$feature_name" >/dev/null || true
  echo "Feature registration requested. It can take several minutes."
done

# Refresh provider metadata after feature registration requests.
echo "Refreshing provider metadata after feature registration."
az provider register --namespace Microsoft.ContainerService >/dev/null || true

echo "Prerequisite checks complete."
