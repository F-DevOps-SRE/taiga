terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Referencia al grupo de recursos existente
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# 1. Módulo de Red
module "network" {
  source              = "./modules/network"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

# 2. Módulo de Almacenamiento
module "storage" {
  source              = "./modules/storage"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

# 3. Módulo de Container Apps
module "container_apps" {
  source               = "./modules/container_apps"
  resource_group_name  = data.azurerm_resource_group.rg.name
  location             = data.azurerm_resource_group.rg.location
  subnet_id            = module.network.subnet_aca_id
  storage_account_name = module.storage.account_name
  storage_account_key  = module.storage.primary_access_key

  postgres_password = var.postgres_password
  rabbitmq_password = var.rabbitmq_pass
  taiga_secret_key  = var.taiga_secret_key
}