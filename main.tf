resource "random_string" "random" {
  count = var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

  length  = 3
  special = false
}

resource "azurerm_log_analytics_workspace" "hpcc" {
  count = var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

  name                               = var.azure_log_analytics_workspace.unique_name ? "${var.azure_log_analytics_workspace.name}-${random_string.random[0].result}" : var.azure_log_analytics_workspace.name
  location                           = var.azure_log_analytics_workspace.location
  resource_group_name                = var.azure_log_analytics_workspace.resource_group_name
  sku                                = var.azure_log_analytics_workspace.sku
  retention_in_days                  = var.azure_log_analytics_workspace.retention_in_days
  daily_quota_gb                     = var.azure_log_analytics_workspace.daily_quota_gb
  internet_ingestion_enabled         = false
  internet_query_enabled             = false
  reservation_capacity_in_gb_per_day = var.azure_log_analytics_workspace.reservation_capacity_in_gb_per_day
  tags                               = var.azure_log_analytics_workspace.tags
}

resource "kubernetes_secret" "log-analytics-workspace" {

  metadata {
    name      = "azure-logaccess"
    namespace = var.hpcc.namespace
  }

  data = {
    "aad-client-id"     = var.azure_log_analytics_creds.AAD_CLIENT_ID
    "aad-tenant-id"     = var.azure_log_analytics_creds.AAD_TENANT_ID
    "aad-client-secret" = var.azure_log_analytics_creds.AAD_CLIENT_SECRET
    "ala-workspace-id"  = try(data.azurerm_log_analytics_workspace.hpcc[0].workspace_id, azurerm_log_analytics_workspace.hpcc[0].workspace_id)
  }

  # type = "basic-auth"
  type = "kubernetes.io/generic"
}

resource "azurerm_role_assignment" "log_analytics_workspace" {

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = var.azure_log_analytics_creds.AAD_PRINCIPAL_ID
}

# resource "azurerm_monitor_private_link_scope" "azure_log_analytics_workspace" {
#   count = var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

#   name                = "${var.azure_log_analytics_workspace.name}-ampls"
#   resource_group_name = var.azure_log_analytics_workspace.resource_group_name
# }

# resource "azurerm_monitor_private_link_scoped_service" "azure_log_analytics_workspace" {
#   count = var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

#   name                = "${var.azure_log_analytics_workspace.name}-amplsservice"
#   resource_group_name = var.azure_log_analytics_workspace.resource_group_name
#   scope_name          = azurerm_monitor_private_link_scope.azure_log_analytics_workspace[0].name
#   linked_resource_id  = azurerm_log_analytics_workspace.hpcc[0].id
# }

# resource "azurerm_private_endpoint" "azure_log_analytics_workspace" {
#   name                = "${var.azure_log_analytics_workspace.name}-endpoint"
#   location            = var.azure_log_analytics_workspace.location //must be same as VNet
#   resource_group_name = var.azure_log_analytics_workspace.resource_group_name
#   subnet_id           = var.subnet_id

#   private_service_connection {
#     name                           = "${var.azure_log_analytics_workspace.name}-privateserviceconnection"
#     private_connection_resource_id = azurerm_monitor_private_link_scoped_service.azure_log_analytics_workspace[0].id
#     is_manual_connection           = false
#   }
# }