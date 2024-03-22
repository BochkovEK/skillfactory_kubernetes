#terraform {
#  required_providers {
#    yandex = {
#      version = "0.103.0"
#      source = "yandex-cloud/yandex"
#    }
#    template = {
#      source = "hashicorp/template"
#      version = "2.2.0"
#    }
#  }
#  required_version = ">= 0.13"
#}

data "yandex_compute_image" "my_image" {
  family = var.instance_family_image
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.yaml")

  vars = {
    vm_user = var.vm_user
    ssh_key_path = file(var.ssh_key_path)
  }
}

output "subnet_id" {
  value = yandex_compute_instance.vm.network_interface[0].subnet_id
}

output "ip_address" {
  value = yandex_compute_instance.vm.network_interface[0].ip_address
  # nat_ip_address  -> external
  # ipv4            -> is true
  # ip_address      -> internal subnet address
}

# Creating a VM

resource "yandex_compute_instance" "vm" {
  name        = "terraform-${var.instance_family_image}"
  zone        = var.zone

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.my_image.id
    }
  }

  network_interface {
    subnet_id          = var.vpc_subnet_id
    nat                = true
    security_group_ids = var.security_group_ids
  }

  metadata = {
	user-data = data.template_file.user_data.rendered
}

}