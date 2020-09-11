/*
  Description:
  Set up infrastructure for sap library 
*/

resource "azurerm_resource_group" "library" {
  count    = local.rg_exists ? 0 : 1
  name     = local.rg_name
  location = local.region
}

// Imports data of existing resource group
data "azurerm_resource_group" "library" {
  count = local.rg_exists ? 1 : 0
  name  = split("/", local.rg_arm_id)[4]
}

// TODO: Add management lock when this issue is addressed https://github.com/terraform-providers/terraform-provider-azurerm/issues/5473

data "azurerm_client_config" "deployer" {}

data "azurerm_user_assigned_identity" "deployer" {
  name                = local.deployer_msi_name
  resource_group_name = local.deployer_rg_name
}

// Create private KV with access policy
resource "azurerm_key_vault" "kv_prvt" {
  name                       = local.kv_private_name
  location                   = local.region
  resource_group_name        = local.rg_exists? data.azurerm_resource_group.library[0].name : local.rg_name
  tenant_id                  = data.azurerm_client_config.deployer.tenant_id
  soft_delete_enabled        = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true
  sku_name                   = "standard"
}

resource "azurerm_key_vault_access_policy" "kv_prvt_msi" {
  key_vault_id = azurerm_key_vault.kv_prvt.id

  tenant_id = data.azurerm_client_config.deployer.tenant_id
  object_id = data.azurerm_user_assigned_identity.deployer.principal_id

  secret_permissions = [
    "get",
  ]
}

// Create user KV with access policy
resource "azurerm_key_vault" "kv_user" {
  name                       = local.kv_user_name
  location                   = local.region
  resource_group_name        = local.rg_exists? data.azurerm_resource_group.library[0].name : local.rg_name
  tenant_id                  = data.azurerm_client_config.deployer.tenant_id
  soft_delete_enabled        = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  sku_name = "standard"
}

resource "azurerm_key_vault_access_policy" "kv_user_msi" {
  key_vault_id = azurerm_key_vault.kv_user.id
  tenant_id = data.azurerm_client_config.deployer.tenant_id
  object_id = data.azurerm_user_assigned_identity.deployer.principal_id

  secret_permissions = [
    "delete",
    "get",
    "list",
    "set",
  ]
}

resource "azurerm_key_vault_access_policy" "kv_user_portal" {
  count = length(local.deployer_users_id)
  key_vault_id = azurerm_key_vault.kv_user.id
  tenant_id = data.azurerm_client_config.deployer.tenant_id
  object_id = local.deployer_users_id[count.index]

  secret_permissions = [
    "delete",
    "get",
    "list",
    "set",
  ]
}

/*
 To force dependency between kv access policy and secrets. Expected behavior:
 https://github.com/terraform-providers/terraform-provider-azurerm/issues/4971
*/
resource "azurerm_key_vault_secret" "downloader_username" {
  depends_on   = [azurerm_key_vault_access_policy.kv_user_portal]
  name         = local.secret_downloader_username_name
  value        = local.downloader_username
  key_vault_id = azurerm_key_vault.kv_user.id
}

resource "azurerm_key_vault_secret" "downloader_password" {
  depends_on   = [azurerm_key_vault_access_policy.kv_user_portal]
  name         = local.secret_downloader_password_name
  value        = local.downloader_password
  key_vault_id = azurerm_key_vault.kv_user.id
}
