# Terraform Formal Azure

Connect an Azure subscription to [Formal](https://joinformal.com) using workload identity federation.

## What it does

This module lets Formal Control Plane federate into your Azure subscription by presenting its AWS identity, which Entra trusts through a federated identity credential. Formal Control Plane then authenticates as a dedicated user-assigned managed identity scoped to your subscription.

In your subscription, it creates:

- a resource group named `fml-<suffix>` to hold the identity, so the module needs no pre-existing group;
- a user-assigned managed identity for Formal to authenticate as;
- a federated identity credential on that identity, pinning Formal's issuer, Formal's per-integration role ARN as the subject, and the `api://AzureADTokenExchange` audience (only that exact role can exchange a token, and Entra matches all three exactly);
- a custom role holding exactly the `actions` and `data_actions` the enabled capabilities use, and one assignment of it, on the subscription or on `resource_group` when set;
- `Storage Blob Data Contributor`, on each account in `blob_storage_accounts`, for log delivery. When no account is named, the blob write is a `data_action` on the custom role instead, covering every account in scope.

No secrets are created. Access is entirely federated.

## Inputs

| Variable                | Description                                                                                                                        |
| ---                     | ---                                                                                                                                |
| `integration_id`        | Formal Cloud Integration id.                                                                                                       |
| `subscription_id`       | Azure subscription to connect.                                                                                                     |
| `issuer`                | OIDC issuer URL of Formal's AWS account. Entra fetches its JWKS to verify Formal's assertion.                                      |
| `subject`               | AWS IAM role ARN Formal presents for your cloud integration. Entra matches it exactly and is case sensitive.                       |
| `audience`              | Audience the assertion carries. Entra only accepts `api://AzureADTokenExchange` (default).                                         |
| `actions`               | Control-plane actions for the custom role, derived from the capabilities you enable.                                               |
| `data_actions`          | Data-plane actions for the custom role, derived the same way.                                                                      |
| `resource_group`        | Narrows discovery and the role assignments to a single resource group. Empty covers the whole subscription (default `""`).         |
| `blob_storage_accounts` | Storage accounts Formal may write logs to. Empty grants blob writes on every account in scope (default `[]`).                      |
| `location`              | Region for the resource group holding Formal's identity. The identity is regional; what it can read is not (default `eastus`). |

## Outputs

| Output      | Description                                                |
| ---         | ---                                                        |
| `tenant_id` | Entra tenant the managed identity belongs to.              |
| `client_id` | Client id of the managed identity Formal authenticates as. |

## Usage

### Via Formal Console

Formal Console shows the exact command, with the id and security key filled in, when you create the Azure integration. Paste it into an authenticated Azure Cloud Shell for the subscription:

```bash
bash <(curl -sSL https://formal.ai/azure.sh) \
  <integration_id> <security_key>
```

It fetches the setup parameters from Formal, runs `terraform apply`, then reports the created tenant and client id back to Formal, which activates the integration.

To change access later (for example after enabling or disabling resource discovery or log delivery on the integration), change the capability on the integration in Formal, then run the same command again. The script keeps its Terraform state in a storage account in your subscription, so a rerun reconciles the granted roles both ways: it adds what the integration now needs and removes what it no longer does.

State is stored as `<integration_id>.tfstate` in a `tfstate` container on a locally redundant storage account named `fml<suffix>`, inside a resource group named `fml-<suffix>-tfstate`, created in the region set by `STATE_LOCATION` (default `eastus`).

### With the Formal Terraform provider

Register the integration, provision the Azure resources with this module, then report them back to activate it:

```hcl
resource "formal_integration_cloud" "azure" {
  name = "my-azure"

  azure {
    subscription_id          = "00000000-0000-0000-0000-000000000000"
    enable_vm_autodiscovery  = true
    enable_aks_autodiscovery = true
    enable_db_autodiscovery  = true
  }
}

module "formal_azure" {
  source = "github.com/formalco/terraform-formal-azure"

  integration_id  = formal_integration_cloud.azure.id
  subscription_id = formal_integration_cloud.azure.azure[0].subscription_id
  issuer          = formal_integration_cloud.azure.azure_issuer
  subject         = formal_integration_cloud.azure.aws_formal_role_arn

  actions      = formal_integration_cloud.azure.azure_actions
  data_actions = formal_integration_cloud.azure.azure_data_actions
}

resource "formal_integration_cloud_azure_activation" "azure" {
  integration_id = formal_integration_cloud.azure.id
  tenant_id      = module.formal_azure.tenant_id
  client_id      = module.formal_azure.client_id
}
```

`issuer`, `subject`, `actions` and `data_actions` come from the integration's computed attributes. `subscription_id` is read from the `azure` block instead, because it feeds `for_each` and so must be known at plan time, as `blob_storage_accounts` does.

Setting `resource_group` or `blob_storage_accounts` on the integration means passing them here too, from the `azure` block. Left out, Azure grants on the whole subscription and on every storage account in it, which is wider than what Formal recorded.

The activation resource is separate from `formal_integration_cloud` on purpose: that resource feeds the module its id and role ARN, so reading the module outputs back into it would create a dependency cycle.

## Notes

- Requires the `azurerm` provider v5. v4 and earlier use a different schema for federated identity credentials.
- This module configures no provider, so point your `azurerm` provider at the same subscription you pass as `subscription_id`, and make sure `Microsoft.ManagedIdentity` is registered on it. `setup.sh` handles both for you.
- A new federated identity credential takes a few minutes to replicate across Entra. Until it does, token exchange can fail with `AADSTS70021`, and Formal retries.
- Public cloud only. Azure Government and 21Vianet use different Entra endpoints and are not supported.
