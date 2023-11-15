locals {
  # Some resources need to be deployed *after* the firewall rules are deployed, or will otherwise fail.
  # For this, we output this value to a local variable, and use it as a dependency for those resources. 
  firewall_rules = {
    core                  = azurerm_firewall_application_rule_collection.core.id
    azure_monitor         = azurerm_firewall_application_rule_collection.azure_monitor.id
  }
}

resource "azurecaf_name" "caf_name_pip" {
  name          = "${var.name}-fw"
  resource_type = "azurerm_public_ip"
}

resource "azurecaf_name" "caf_name_firewall" {
  name          = var.name
  resource_type = "azurerm_firewall"
}

resource "azurerm_public_ip" "firewall_pip" {
  name                = azurecaf_name.caf_name_pip.result
  resource_group_name = var.resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

resource "azurerm_firewall" "firewall" {
  name                = azurecaf_name.caf_name_firewall.result
  resource_group_name = var.resource_group
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "firewallIpConfiguration"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }

  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "${azurerm_firewall.firewall.name}-diagnostic-settings"
  target_resource_id         = azurerm_firewall.firewall.id
  log_analytics_workspace_id = var.log_analytics_workspace_id == null ? azurerm_log_analytics_workspace.law.0.id : var.log_analytics_workspace_id
  # log_analytics_destination_type = "AzureDiagnostics"

  enabled_log {
    category_group = "allLogs"

    ## `retention_policy` has been deprecated in favor of `azurerm_storage_management_policy` resource - to learn more https://aka.ms/diagnostic_settings_log_retention
    # retention_policy {
    #   days    = 0
    #   enabled = false
    # }
  }

  metric {
    category = "AllMetrics"
    enabled  = false

    ## `retention_policy` has been deprecated in favor of `azurerm_storage_management_policy` resource - to learn more https://aka.ms/diagnostic_settings_log_retention
    # retention_policy {
    #   days    = 0
    #   enabled = false
    # }
  }

  depends_on = [
    azurerm_firewall.firewall
  ]
}

resource "azurerm_firewall_application_rule_collection" "core" {
  name                = "Core-Dependencies-FQDNs"
  azure_firewall_name = azurerm_firewall.firewall.name
  resource_group_name = var.resource_group
  priority            = 200
  action              = "Allow"

  rule {
    name = "allow-core-apis"

    source_addresses = var.firewall_rules_source_addresses

    target_fqdns = [
      "management.azure.com",
      "management.core.windows.net",
      "login.microsoftonline.com",
      "login.windows.net",
      "login.live.com",
      "graph.windows.net",
      "graph.microsoft.com"
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }

  rule {
    name = "allow-developer-services"

    # Access to developer services is needed from the App Service integration subnet *if* Deployment Center is used. 
    # Otherwise, this rule can be applied to the DevOps subnet:
    # https://learn.microsoft.com/en-us/azure/app-service/deploy-continuous-deployment
    source_addresses = var.firewall_rules_source_addresses

    target_fqdns = [
      "github.com",
      "*.github.com",
      "*.nuget.org",
      "*.blob.core.windows.net",
      "*.githubusercontent.com",
      "dev.azure.com",
      "*.dev.azure.com",
      "portal.azure.com",
      "*.portal.azure.com",
      "*.portal.azure.net",
      "appservice.azureedge.net",
      "*.azurewebsites.net",
      "edge.management.azure.com",
      "vstsagentpackage.azureedge.net"
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }

  rule {
    name = "allow-certificate-dependencies"

    source_addresses = var.firewall_rules_source_addresses

    target_fqdns = [
      "*.delivery.mp.microsoft.com",
      "ctldl.windowsupdate.com",
      "download.windowsupdate.com",
      "mscrl.microsoft.com",
      "ocsp.msocsp.com",
      "oneocsp.microsoft.com",
      "crl.microsoft.com",
      "www.microsoft.com",
      "*.digicert.com",
      "*.symantec.com",
      "*.symcb.com",
      "*.d-trust.net",
    ]

    protocol {
      port = "80"
      type = "Http"
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "azure_monitor" {
  name                = "Azure-Monitor-FQDNs"
  azure_firewall_name = azurerm_firewall.firewall.name
  resource_group_name = var.resource_group
  priority            = 201
  action              = "Allow"

  rule {
    name = "allow-azure-monitor"

    source_addresses = var.firewall_rules_source_addresses

    target_fqdns = [
      "dc.applicationinsights.azure.com",
      "dc.applicationinsights.microsoft.com",
      "dc.services.visualstudio.com",
      "*.in.applicationinsights.azure.com",
      "live.applicationinsights.azure.com",
      "rt.applicationinsights.microsoft.com",
      "rt.services.visualstudio.com",
      "*.livediagnostics.monitor.azure.com",
      "*.monitoring.azure.com",
      "agent.azureserviceprofiler.net",
      "*.agent.azureserviceprofiler.net",
      "*.monitor.azure.com"
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }
}
