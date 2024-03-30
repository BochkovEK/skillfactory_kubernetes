variable "k8s_version" {
  type = string
}

variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

#variable "service_account_id" {
#  type = string
#}

variable "service_account_name" {
  type = string
}

variable "zone_name" {
  type = string
}

variable "ssh_key_path" {
  description = "ssh_key_path"
  type        = string
}

variable "vm_user" {
  description = "vm_user"
  type        = string
}

variable "registry_name" {
  description = "registry_name"
  type        = string
}

