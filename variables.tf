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

variable "role_definitions" {
  type        = list(string)
  description = "Azure built-in roles to grant Formal's managed identity, derived from the capabilities you enable. Storage Blob Data Contributor is applied per storage account when blob_storage_accounts is set, and on the whole subscription or resource group otherwise."
  default     = []
  nullable    = false
}

variable "blob_storage_accounts" {
  type        = list(string)
  description = "Storage accounts Formal may write logs to. An empty list grants blob writes on every account in the subscription, or in resource_group when set; a non-empty list restricts them to those accounts."
  default     = []
  nullable    = false
}
