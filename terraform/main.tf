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
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.18"
    }
  }

  # Estado remoto en Azure Storage. La cuenta (stdevopssre) se creó a mano y no
  # la administra este Terraform: el estado no puede vivir en lo que él mismo describe.
  backend "azurerm" {
    resource_group_name  = "rg-taiga"
    storage_account_name = "stdevopssre"
    container_name       = "tfstate"
    key                  = "taiga.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# La API key se lee de la variable de entorno NEON_API_KEY (secreto en el workflow).
provider "neon" {}

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

# 3. Base de datos en Neon (fuera de Azure)
module "neon" {
  source = "./modules/neon"
  org_id = "org-wispy-cloud-84381910"
}

# El proyecto se creó desde la consola de Neon: el primer apply lo agrega al estado
# sin tocarlo. Después de eso este bloque no hace nada.
import {
  to = module.neon.neon_project.taiga
  id = "restless-star-54395891"
}

# 4. Módulo de Container Apps
module "container_apps" {
  source               = "./modules/container_apps"
  resource_group_name  = data.azurerm_resource_group.rg.name
  location             = data.azurerm_resource_group.rg.location
  subnet_id            = module.network.subnet_aca_id
  storage_account_name = module.storage.account_name
  storage_account_key  = module.storage.primary_access_key
  storage_share_name   = module.storage.share_name

  postgres_host     = module.neon.host
  postgres_db       = module.neon.database
  postgres_user     = module.neon.user
  postgres_password = module.neon.password
  rabbitmq_password = var.rabbitmq_pass
  taiga_secret_key  = var.taiga_secret_key

  # Imágenes publicadas en GHCR (sha-<commit>) y gateway de docker-compose
  image_registry         = var.image_registry
  taiga_back_commit      = var.taiga_back_commit
  taiga_front_commit     = var.taiga_front_commit
  taiga_events_commit    = var.taiga_events_commit
  taiga_protected_commit = var.taiga_protected_commit
  gateway_nginx_conf     = file("${path.root}/../taiga-gateway/nginx.conf")

  alert_email               = var.alert_email
  availability_test_enabled = var.availability_test_enabled
}
