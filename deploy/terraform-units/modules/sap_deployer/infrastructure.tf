/*
Description:

  Define infrastructure resources for deployer(s).
*/

// Random 8 char identifier for each sap deployer
resource "random_id" "deployer" {
  byte_length = 4
}

// Create managed resource group for sap deployer with CanNotDelete lock
resource "azurerm_resource_group" "deployer" {
  name     = local.rg_name
  location = local.region
}

resource "azurerm_management_lock" "deployer" {
  name       = "resource-group-level"
  scope      = azurerm_resource_group.deployer.id
  lock_level = "CanNotDelete"
  notes      = "Locked because it's needed by Azure Automated Deployment"
}

// Create/Import management vnet
resource "azurerm_virtual_network" "vnet-mgmt" {
  count               = local.vnet_mgmt_exists ? 0 : 1
  name                = local.vnet_mgmt_name
  location            = azurerm_resource_group.deployer.location
  resource_group_name = azurerm_resource_group.deployer.name
  address_space       = [local.vnet_mgmt_addr]
}

data "azurerm_virtual_network" "vnet-mgmt" {
  count               = local.vnet_mgmt_exists ? 1 : 0
  name                = split("/", local.vnet_mgmt_arm_id)[8]
  resource_group_name = split("/", local.vnet_mgmt_arm_id)[4]
}

// Create/Import management subnet
resource "azurerm_subnet" "subnet-mgmt" {
  count                = local.sub_mgmt_exists ? 0 : 1
  name                 = local.sub_mgmt_name
  resource_group_name  = local.vnet_mgmt_exists ? data.azurerm_virtual_network.vnet-mgmt[0].resource_group_name : azurerm_virtual_network.vnet-mgmt[0].resource_group_name
  virtual_network_name = local.vnet_mgmt_exists ? data.azurerm_virtual_network.vnet-mgmt[0].name : azurerm_virtual_network.vnet-mgmt[0].name
  address_prefixes     = [local.sub_mgmt_prefix]
}

data "azurerm_subnet" "subnet-mgmt" {
  count                = local.sub_mgmt_exists ? 1 : 0
  name                 = split("/", local.sub_mgmt_arm_id)[10]
  resource_group_name  = split("/", local.sub_mgmt_arm_id)[4]
  virtual_network_name = split("/", local.sub_mgmt_arm_id)[8]
}

// Creates boot diagnostics storage account for Deployer
resource "azurerm_storage_account" "deployer" {
  name                      = "sadiag${local.postfix}"
  resource_group_name       = azurerm_resource_group.deployer.name
  location                  = azurerm_resource_group.deployer.location
  account_replication_type  = "LRS"
  account_tier              = "Standard"
  enable_https_traffic_only = local.enable_secure_transfer
}

// Creates storage account with container for remote state files, soft deletion enabled
resource "azurerm_storage_account" "tfstate" {
  name                      = "sapdeployer${local.postfix}"
  resource_group_name       = azurerm_resource_group.deployer.name
  location                  = azurerm_resource_group.deployer.location
  account_replication_type  = "LRS"
  account_tier              = "Standard"
  enable_https_traffic_only = local.enable_secure_transfer
  delete_retention_policy {
    days = 7
  }
}

resource "azurerm_storage_container" "container" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

