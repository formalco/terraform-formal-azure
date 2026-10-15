variable "integration_id" {
  type        = string
  description = "The Formal cloud integration id (a typeid, e.g. integrationcloud_01hxxxxxxxxxxxxxxxxxxxxxxx). The part after the underscore is used to derive resource names."

  validation {
    condition     = can(regex("_[a-z0-9]{26}$", var.integration_id))
    error_message = "integration_id must be a typeid ending in an underscore followed by a 26-character suffix."
  }
}

variable "issuer" {
  type        = string
  description = "OIDC issuer URL of Formal's AWS account, from GetAzureCloudIntegrationSetup. Entra fetches its JWKS to verify Formal's assertion."

  validation {
    condition     = can(regex("^https://", var.issuer))
    error_message = "issuer must be an https URL."
  }
}

variable "subject" {
  type        = string
  description = "The per-integration AWS IAM role ARN Formal presents as the assertion subject. Entra matches it exactly and is case sensitive, so pass it through unchanged."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.subject))
    error_message = "subject must be an AWS IAM role ARN."
  }
}

variable "audience" {
  type        = string
  description = "Audience the assertion carries. Entra only accepts api://AzureADTokenExchange."
  default     = "api://AzureADTokenExchange"
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription to connect to Formal."
}

variable "resource_group" {
  type        = string
  description = "Narrows autodiscovery and every subscription-level role assignment to a single resource group. Empty covers the whole subscription."
  default     = ""
  nullable    = false
}

variable "location" {
  type        = string
  description = "Azure region for the resource group holding Formal's managed identity. The identity is regional; what it can read is not."
  default     = "eastus"
}

variable "actions" {
  type        = list(string)
  description = "Control-plane actions to grant Formal's managed identity through a custom role, derived from the capabilities you enable. Pass azure_actions from the integration."
  nullable    = false

  validation {
    condition     = length(var.actions) > 0
    error_message = "actions is empty, but Formal always returns at least one. Pass azure_actions from formal_integration_cloud."
  }
}

variable "data_actions" {
  type        = list(string)
  description = "Data-plane actions to grant through the same custom role, derived from the capabilities you enable. Empty when blob_storage_accounts names specific accounts, because blob writes are then granted per account instead. Pass azure_data_actions from the integration."
  nullable    = false
}

variable "role_definitions" {
  type        = list(string)
  description = "Removed: superseded by actions and data_actions, which grant a custom role scoped to what Formal actually calls instead of built-in roles."
  default     = []
  nullable    = false

  validation {
    condition     = length(var.role_definitions) == 0
    error_message = "role_definitions is no longer supported. Pass actions = formal_integration_cloud.<name>.azure_actions and data_actions = formal_integration_cloud.<name>.azure_data_actions instead, with a Formal provider version that exposes them."
  }
}

variable "blob_storage_accounts" {
  type        = list(string)
  description = "Storage accounts Formal may write logs to. An empty list grants blob writes on every account in the subscription, or in resource_group when set; a non-empty list restricts them to those accounts."
  default     = []
  nullable    = false
}
