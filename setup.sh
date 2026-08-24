#!/usr/bin/env bash
#
# Connect an Azure subscription to Formal via workload identity federation.
#
# Run this inside an authenticated Azure Cloud Shell for the subscription you
# want to connect. It fetches the integration parameters from Formal, applies the
# Terraform in this repo, then reports the created managed identity back to
# Formal, which activates the integration. Formal shows the exact command when
# you create the Azure integration.
#
# Usage:
#   ./setup.sh <integration_id> <security_key>
#
# FORMAL_API_URL defaults to production; override it for other environments.

set -euo pipefail

INTEGRATION_ID="${1:-}"
SECURITY_KEY="${2:-}"
FORMAL_API_URL="${FORMAL_API_URL:-https://api.joinformal.com}"

if [[ -z "${INTEGRATION_ID}" || -z "${SECURITY_KEY}" ]]; then
  echo "Usage: $0 <integration_id> <security_key>" >&2
  exit 1
fi

SETUP="$(curl -fsS -X POST \
  "${FORMAL_API_URL%/}/core.v1.IntegrationCloudService/GetAzureCloudIntegrationSetup" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"${INTEGRATION_ID}\",\"securityKey\":\"${SECURITY_KEY}\"}")"

ISSUER="$(jq -r '.issuer' <<<"${SETUP}")"
SUBJECT="$(jq -r '.subject' <<<"${SETUP}")"
AUDIENCE="$(jq -r '.audience' <<<"${SETUP}")"
SUBSCRIPTION_ID="$(jq -r '.subscriptionId' <<<"${SETUP}")"
RESOURCE_GROUP="$(jq -r '.resourceGroup // ""' <<<"${SETUP}")"
ROLE_DEFINITIONS="$(jq -c '.roleDefinitions // []' <<<"${SETUP}")"
BLOB_STORAGE_ACCOUNTS="$(jq -c '.blobStorageAccounts // []' <<<"${SETUP}")"

REPO_URL="https://github.com/formalco/terraform-formal-azure.git"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If setup.sh was piped/curled rather than run from a checkout, clone the repo.
if [[ ! -f "${WORKDIR}/main.tf" ]]; then
  WORKDIR="$(mktemp -d)/terraform-formal-azure"
  git clone --depth 1 "${REPO_URL}" "${WORKDIR}"
fi

cd "${WORKDIR}/setup"

# Fetch terraform binary when the real one isn't already on PATH.
TERRAFORM=terraform
if ! terraform version 2>/dev/null | grep -q '^Terraform v'; then
  TF_VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"
  TF_ARCH="$(uname -m)"
  case "${TF_ARCH}" in
    x86_64) TF_ARCH=amd64 ;;
    aarch64 | arm64) TF_ARCH=arm64 ;;
  esac
  TF_DIR="$(mktemp -d)"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip" -o "${TF_DIR}/terraform.zip"
  unzip -q -o "${TF_DIR}/terraform.zip" -d "${TF_DIR}"
  TERRAFORM="${TF_DIR}/terraform"
fi

TF_VARS=(
  -var "integration_id=${INTEGRATION_ID}"
  -var "subscription_id=${SUBSCRIPTION_ID}"
  -var "resource_group=${RESOURCE_GROUP}"
  -var "issuer=${ISSUER}"
  -var "subject=${SUBJECT}"
  -var "audience=${AUDIENCE}"
  -var "role_definitions=${ROLE_DEFINITIONS}"
  -var "blob_storage_accounts=${BLOB_STORAGE_ACCOUNTS}"
)

# Keep Terraform state in a storage account in this subscription so reruns
# reconcile access both ways instead of starting blank. Override the region with
# STATE_LOCATION; versioning allows rolling back a bad apply.
STATE_RESOURCE_GROUP="fml-${INTEGRATION_ID##*_}-tfstate"
# Storage account names are 3-24 chars, lowercase alphanumeric only.
STATE_ACCOUNT="fml$(tr -dc 'a-z0-9' <<<"${INTEGRATION_ID##*_}" | cut -c1-21)"
STATE_CONTAINER="tfstate"
STATE_LOCATION="${STATE_LOCATION:-eastus}"

az account set --subscription "${SUBSCRIPTION_ID}"

# azurerm v5 registers nothing on its own.
az provider register --namespace Microsoft.ManagedIdentity --wait

if ! az group show --name "${STATE_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az group create --name "${STATE_RESOURCE_GROUP}" --location "${STATE_LOCATION}" >/dev/null
fi

if ! az storage account show --name "${STATE_ACCOUNT}" --resource-group "${STATE_RESOURCE_GROUP}" >/dev/null 2>&1; then
  az storage account create \
    --name "${STATE_ACCOUNT}" \
    --resource-group "${STATE_RESOURCE_GROUP}" \
    --location "${STATE_LOCATION}" \
    --sku Standard_LRS \
    --allow-blob-public-access false >/dev/null
fi

az storage account blob-service-properties update \
  --account-name "${STATE_ACCOUNT}" \
  --resource-group "${STATE_RESOURCE_GROUP}" \
  --enable-versioning true >/dev/null

# Owning a storage account grants no blob access, and both the container create
# and the Terraform backend authenticate with Entra.
STATE_ACCOUNT_ID="$(az storage account show \
  --name "${STATE_ACCOUNT}" \
  --resource-group "${STATE_RESOURCE_GROUP}" \
  --query id -o tsv)"

PRINCIPAL_TYPE=User
PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -z "${PRINCIPAL_ID}" ]]; then
  PRINCIPAL_TYPE=ServicePrincipal
  PRINCIPAL_ID="$(az ad sp show --id "$(az account show --query user.name -o tsv)" --query id -o tsv 2>/dev/null || true)"
fi

if [[ -z "${PRINCIPAL_ID}" ]]; then
  echo "Could not resolve the signed-in principal. Run 'az login' and retry." >&2
  exit 1
fi

if ! az role assignment list \
  --assignee "${PRINCIPAL_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "${STATE_ACCOUNT_ID}" \
  --query "[0].id" -o tsv | grep -q .; then
  az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id "${PRINCIPAL_ID}" \
    --assignee-principal-type "${PRINCIPAL_TYPE}" \
    --scope "${STATE_ACCOUNT_ID}" >/dev/null
fi

# A new role assignment takes a while to reach the data plane.
for attempt in $(seq 1 30); do
  if az storage container create \
    --name "${STATE_CONTAINER}" \
    --account-name "${STATE_ACCOUNT}" \
    --auth-mode login >/dev/null 2>&1; then
    break
  fi
  if [[ "${attempt}" -eq 30 ]]; then
    echo "Timed out waiting for blob access to ${STATE_ACCOUNT}. Last error:" >&2
    az storage container create \
      --name "${STATE_CONTAINER}" \
      --account-name "${STATE_ACCOUNT}" \
      --auth-mode login >/dev/null || true
    exit 1
  fi
  sleep 10
done

"${TERRAFORM}" init -input=false \
  -backend-config="resource_group_name=${STATE_RESOURCE_GROUP}" \
  -backend-config="storage_account_name=${STATE_ACCOUNT}" \
  -backend-config="container_name=${STATE_CONTAINER}" \
  -backend-config="key=${INTEGRATION_ID}.tfstate"

"${TERRAFORM}" apply -input=false -auto-approve "${TF_VARS[@]}"

TENANT_ID="$("${TERRAFORM}" output -raw tenant_id)"
CLIENT_ID="$("${TERRAFORM}" output -raw client_id)"

# Entra needs a moment to replicate a new federated identity credential, so the
# first token exchange can fail with AADSTS70021 even though setup succeeded.
curl -fsS -X POST \
  "${FORMAL_API_URL%/}/core.v1.IntegrationCloudService/SetAzureCloudIntegrationActivation" \
  -H "Content-Type: application/json" \
  -d "$(cat <<JSON
{"id":"${INTEGRATION_ID}","securityKey":"${SECURITY_KEY}","tenantId":"${TENANT_ID}","clientId":"${CLIENT_ID}"}
JSON
)"

echo
echo "Done. Formal is now connected to subscription ${SUBSCRIPTION_ID}."
