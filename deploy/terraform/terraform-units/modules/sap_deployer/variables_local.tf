/*
Description:

  Define local variables.
*/

variable "region_mapping" {
  type        = map(string)
  description = "Region Mapping: Full = Single CHAR, 4-CHAR"

  # 28 Regions 

  default = {
    westus             = "weus"
    westus2            = "wus2"
    centralus          = "ceus"
    eastus             = "eaus"
    eastus2            = "eus2"
    northcentralus     = "ncus"
    southcentralus     = "scus"
    westcentralus      = "wcus"
    northeurope        = "noeu"
    westeurope         = "weeu"
    eastasia           = "eaas"
    southeastasia      = "seas"
    brazilsouth        = "brso"
    japaneast          = "jpea"
    japanwest          = "jpwe"
    centralindia       = "cein"
    southindia         = "soin"
    westindia          = "wein"
    uksouth2           = "uks2"
    uknorth            = "ukno"
    canadacentral      = "cace"
    canadaeast         = "caea"
    australiaeast      = "auea"
    australiasoutheast = "ause"
    uksouth            = "ukso"
    ukwest             = "ukwe"
    koreacentral       = "koce"
    koreasouth         = "koso"
  }
}

// Set defaults
locals {

  // Post fix for all deployed resources
  postfix = random_id.deployer.hex

  // Default option(s):
  enable_secure_transfer = try(var.options.enable_secure_transfer, true)

  // Resource group and location

  region             = try(var.infrastructure.region, "")
  landscape          = try(var.infrastructure.landscape, "")
  location_short     = try(var.region_mapping[local.region], "unkn")
  vnet_mgmt_tempname = try(local.vnet_mgmt.name, "deployer")
  prefix             = try(var.infrastructure.resource_group.name, upper(format("%s-%s-%s", local.landscape, local.location_short, local.vnet_mgmt_tempname)))
  sa_prefix          = lower(format("%s%s%sdiag", substr(local.landscape, 0, 5), local.location_short, substr(local.vnet_mgmt_tempname, 0, 7)))
  kv_prefix          = upper(format("%s%s%s", substr(local.landscape, 0, 5), local.location_short, substr(local.vnet_mgmt_tempname, 0, 7)))
  rg_name            = try(var.infrastructure.resource_group.name, format("%s-INFRASTRUCTURE", local.prefix))


  // Management vnet
  vnet_mgmt        = try(var.infrastructure.vnets.management, {})
  vnet_mgmt_exists = try(local.vnet_mgmt.is_existing, false)
  vnet_mgmt_arm_id = local.vnet_mgmt_exists ? try(local.vnet_mgmt.arm_id, "") : ""
  vnet_mgmt_name   = local.vnet_mgmt_exists ? "" : try(local.vnet_mgmt.name, format("%s-vnet", local.prefix))
  vnet_mgmt_addr   = local.vnet_mgmt_exists ? "" : try(local.vnet_mgmt.address_space, "10.0.0.0/24")

  // Management subnet
  sub_mgmt          = try(local.vnet_mgmt.subnet_mgmt, {})
  sub_mgmt_exists   = try(local.sub_mgmt.is_existing, false)
  sub_mgmt_arm_id   = local.sub_mgmt_exists ? try(local.sub_mgmt.arm_id, "") : ""
  sub_mgmt_name     = local.sub_mgmt_exists ? "" : try(local.sub_mgmt.name, format("%s_deployment-subnet", local.prefix))
  sub_mgmt_prefix   = local.sub_mgmt_exists ? "" : try(local.sub_mgmt.prefix, "10.0.0.16/28")
  sub_mgmt_deployed = try(local.sub_mgmt_exists ? data.azurerm_subnet.subnet_mgmt[0] : azurerm_subnet.subnet_mgmt[0], null)

  // Management NSG
  sub_mgmt_nsg             = try(local.sub_mgmt.nsg, {})
  sub_mgmt_nsg_exists      = try(local.sub_mgmt_nsg.is_existing, false)
  sub_mgmt_nsg_arm_id      = local.sub_mgmt_nsg_exists ? try(local.sub_mgmt_nsg.arm_id, "") : ""
  sub_mgmt_nsg_name        = local.sub_mgmt_nsg_exists ? "" : try(local.sub_mgmt_nsg.name, format("%s_deploymentSubnet-nsg", local.prefix))
  deployer_pip_list        = azurerm_public_ip.deployer[*].ip_address
  sub_mgmt_nsg_allowed_ips = local.sub_mgmt_nsg_exists ? [] : try(concat(local.sub_mgmt_nsg.allowed_ips, local.deployer_pip_list), ["0.0.0.0/0"])
  sub_mgmt_nsg_deployed    = try(local.sub_mgmt_nsg_exists ? data.azurerm_network_security_group.nsg_mgmt[0] : azurerm_network_security_group.nsg_mgmt[0], null)

  // Deployer(s) information from input
  deployer_input = var.deployers

  enable_key = contains(compact([
    for deployer in local.deployer_input :
    try(deployer.authentication.type, "key") == "key" ? true : false
  ]), "true")

  // By default use generated public key. Provide sshkey.path_to_public_key and path_to_private_key overides it
  public_key  = (local.enable_deployers && local.enable_key) ? try(file(var.sshkey.path_to_public_key), tls_private_key.deployer[0].public_key_openssh) : null
  private_key = (local.enable_deployers && local.enable_key) ? try(file(var.sshkey.path_to_private_key), tls_private_key.deployer[0].private_key_pem) : null

  // Deployer(s) information with default override
  enable_deployers = length(local.deployer_input) > 0 ? true : false
  deployers = [
    for idx, deployer in local.deployer_input : {
      "name"                 = "deployer",
      "destroy_after_deploy" = true,
      "size"                 = try(deployer.size, "Standard_D2s_v3"),
      "disk_type"            = try(deployer.disk_type, "StandardSSD_LRS")
      "os" = {
        "source_image_id" = try(deployer.os.source_image_id, "")
        "publisher"       = try(deployer.os.source_image_id, "") == "" ? "Canonical" : ""
        "offer"           = try(deployer.os.source_image_id, "") == "" ? "UbuntuServer" : ""
        "sku"             = try(deployer.os.source_image_id, "") == "" ? "18.04-LTS" : ""
        "version"         = try(deployer.os.source_image_id, "") == "" ? "latest" : ""
      },
      "authentication" = {
        "type"     = "key",
        "username" = try(deployer.authentication.username, "azureadm"),
        "sshkey" = {
          "public_key"  = local.public_key
          "private_key" = local.private_key
        }
      },
      "components" = [
        "terraform",
        "ansible"
      ],
      "private_ip_address" = try(deployer.private_ip_address, cidrhost(local.sub_mgmt_deployed.address_prefixes[0], idx + 4))
    }
  ]

  // Deployer(s) information with updated pip
  deployers_updated = [
    for idx, deployer in local.deployers : merge({
      "public_ip_address" = azurerm_public_ip.deployer[idx].ip_address
    }, deployer)
  ]

}
