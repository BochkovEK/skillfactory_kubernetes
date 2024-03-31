terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

// Configure the Yandex.Cloud provider
provider "yandex" {
  #token                    = "auth_token_here"
  service_account_key_file = "/root/admin.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone_name
}