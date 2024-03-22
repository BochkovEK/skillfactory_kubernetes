# Instances

variable "instance_family_image" {
  description = "Instance image"
  type        = string
  default     = "ubuntu-2004-lts"
}

variable "vpc_subnet_id" {
  description = "subnet_id"
  type        = string
}

variable "security_group_ids" {
  description = "security_group_ids"
  type        = list(string)
}

variable "vm_user" {
  description = "vm_user"
  type        = string
}

variable "ssh_key_path" {
  description = "ssh_key_path"
  type        = string
}

variable "zone" {
  description = "zone"
  type        = string
}
