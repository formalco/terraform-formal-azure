terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # v5 replaced the federated credential's resource_group_name/parent_id pair
      # with user_assigned_identity_id, so this is not compatible with v4.
      version = "~> 5.0"
    }
  }
}
