terraform {
  required_version = ">= 1.3"

  # Backend blocks take no variables, so setup.sh passes the rest at init time.
  backend "azurerm" {
    use_azuread_auth = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

variable "integration_id" {
  type = string
}

variable "issuer" {
  type = string
}

variable "subject" {
  type = string
}

variable "audience" {
  type    = string
  default = "api://AzureADTokenExchange"
}

variable "subscription_id" {
  type = string
}

variable "resource_group" {
  type     = string
  default  = ""
  nullable = false
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "actions" {
  type     = list(string)
  default  = []
  nullable = false
}

variable "data_actions" {
  type     = list(string)
  default  = []
  nullable = false
}

variable "blob_storage_accounts" {
  type     = list(string)
  default  = []
  nullable = false
}

module "formal" {
  source = "../"

  integration_id        = var.integration_id
  issuer                = var.issuer
  subject               = var.subject
  audience              = var.audience
  subscription_id       = var.subscription_id
  resource_group        = var.resource_group
  location              = var.location
  actions               = var.actions
  data_actions          = var.data_actions
  blob_storage_accounts = var.blob_storage_accounts
}

output "tenant_id" {
  value = module.formal.tenant_id
}

output "client_id" {
  value = module.formal.client_id
}
