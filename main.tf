locals {
  suffix = element(split("_", var.integration_id), length(split("_", var.integration_id)) - 1)
  name   = "fml-${local.suffix}"

  # The whole subscription unless a resource group narrows it.
  scope = var.resource_group == "" ? "/subscriptions/${var.subscription_id}" : "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group}"
}

# The identity needs a resource group of its own so this module does not depend on
# any pre-existing group in the subscription.
resource "azurerm_resource_group" "this" {
  name     = local.name
  location = var.location
}

resource "azurerm_user_assigned_identity" "this" {
  name                = local.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

# Entra compares issuer, subject and audience exactly and does not support
# wildcards, so these are passed through from Formal verbatim rather than
# reconstructed here. Only Formal's per-integration role can present a token
# whose `sub` is this subject.
resource "azurerm_federated_identity_credential" "this" {
  name                      = local.name
  user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  issuer                    = var.issuer
  subject                   = var.subject
  audience                  = [var.audience]
}

# Formal derives the actions, so they are unknown until apply, which rules out for_each.
resource "azurerm_role_definition" "this" {
  name        = local.name
  scope       = local.scope
  description = "Formal cloud integration ${var.integration_id}"

  permissions {
    actions      = var.actions
    data_actions = var.data_actions
  }

  assignable_scopes = [local.scope]
}

resource "azurerm_role_assignment" "this" {
  scope              = local.scope
  role_definition_id = azurerm_role_definition.this.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.this.principal_id

  # The identity is created in this same apply, so the directory check would fail
  # on Entra replication lag.
  skip_service_principal_aad_check = true
}

# Formal only knows the storage account names, and they need not live in the
# resource group above, so resolve each id from the subscription.
data "azurerm_resources" "log_storage_accounts" {
  for_each = toset(var.blob_storage_accounts)

  name = each.value
  type = "Microsoft.Storage/storageAccounts"
}

# Blob writes are a data-plane action, so they are granted per storage account
# rather than on the whole subscription.
resource "azurerm_role_assignment" "log_storage_accounts" {
  for_each = toset(var.blob_storage_accounts)

  scope                = one(data.azurerm_resources.log_storage_accounts[each.key].resources).id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id

  skip_service_principal_aad_check = true
}
