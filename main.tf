resource "random_string" "random" {
  count = can(var.azure_log_analytics_workspace.use_existing_workspace) ? 0 : 1

  length  = 3
  special = false
}

resource "azurerm_log_analytics_workspace" "hpcc" {
  count = can(var.azure_log_analytics_workspace) && var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

  name                               = can(var.azure_log_analytics_workspace.unique_name == true) ? "${var.azure_log_analytics_workspace.name}-${random_string.random[0].result}" : var.azure_log_analytics_workspace.name
  location                           = var.azure_log_analytics_workspace.location
  resource_group_name                = var.azure_log_analytics_workspace.resource_group_name
  sku                                = var.azure_log_analytics_workspace.sku
  retention_in_days                  = var.azure_log_analytics_workspace.retention_in_days
  daily_quota_gb                     = var.azure_log_analytics_workspace.daily_quota_gb
  internet_ingestion_enabled         = var.azure_log_analytics_workspace.internet_ingestion_enabled
  internet_query_enabled             = var.azure_log_analytics_workspace.internet_query_enabled
  reservation_capacity_in_gb_per_day = var.azure_log_analytics_workspace.reservation_capacity_in_gb_per_day
  tags                               = var.azure_log_analytics_workspace.tags
}

resource "kubernetes_secret" "azure_log_analytics_workspace" {

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

resource "azurerm_role_assignment" "azure_log_analytics_workspace" {

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = var.azure_log_analytics_creds.AAD_PRINCIPAL_ID
}

resource "azurerm_monitor_private_link_scope" "azure_log_analytics_workspace" {
  count = can(var.azure_log_analytics_workspace) && var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

  name                = "${var.azure_log_analytics_workspace.name}-ampls"
  resource_group_name = var.azure_log_analytics_workspace.resource_group_name
}

resource "azurerm_monitor_private_link_scoped_service" "azure_log_analytics_workspace" {
  count = can(var.azure_log_analytics_workspace) && var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

  name                = "${var.azure_log_analytics_workspace.name}-amplsservice"
  resource_group_name = var.azure_log_analytics_workspace.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.azure_log_analytics_workspace[0].name
  linked_resource_id  = azurerm_log_analytics_workspace.hpcc[0].id
}

resource "azurerm_private_dns_zone" "azure_log_analytics_workspace" {
  for_each = can(var.azure_log_analytics_workspace) && var.azure_log_analytics_workspace.use_existing_workspace == null ? local.privatelink_dns : {}

  name                = each.value
  resource_group_name = var.azure_log_analytics_workspace.resource_group_name
}

resource "azurerm_private_endpoint" "azure_log_analytics_workspace" {
  count = can(var.azure_log_analytics_workspace) && var.azure_log_analytics_workspace.use_existing_workspace == null ? 1 : 0

  name                = "${var.azure_log_analytics_workspace.name}-endpoint"
  location            = var.azure_log_analytics_workspace.location //must be same as VNet
  resource_group_name = var.azure_log_analytics_workspace.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.azure_log_analytics_workspace.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_monitor_private_link_scope.azure_log_analytics_workspace[0].id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [for v in azurerm_private_dns_zone.azure_log_analytics_workspace : v.id]
  }
}

resource "azurerm_log_analytics_linked_storage_account" "azure_log_analytics_workspace" {
  count = can(var.azure_log_analytics_workspace) && can(var.azure_log_analytics_workspace.linked_storage_account) ? 1 : 0

  data_source_type      = var.azure_log_analytics_workspace.linked_storage_account.data_source_type
  resource_group_name   = can(var.azure_log_analytics_workspace.use_existing_workspace) ? var.azure_log_analytics_workspace.use_existing_workspace.resource_group_name : var.azure_log_analytics_workspace.resource_group_name
  workspace_resource_id = can(var.azure_log_analytics_workspace.use_existing_workspace) ? data.azurerm_log_analytics_workspace.hpcc[0].id : azurerm_log_analytics_workspace.hpcc[0].id
  storage_account_ids   = var.azure_log_analytics_workspace.linked_storage_account.storage_account_ids
}
