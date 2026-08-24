output "tenant_id" {
  description = "Entra tenant the managed identity belongs to, reported back to Formal."
  value       = azurerm_user_assigned_identity.this.tenant_id
}

output "client_id" {
  description = "Client id of the managed identity Formal authenticates as, reported back to Formal."
  value       = azurerm_user_assigned_identity.this.client_id
}
