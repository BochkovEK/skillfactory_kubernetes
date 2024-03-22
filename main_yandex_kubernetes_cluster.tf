
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

// Configure the Yandex.Cloud provider
// Folder id (skillfactory: b1g93fsq8gqfkrjj0t2k)
// Cloud id (cloud-hoy85: b1g3fuk1gs418fa34ng4)
provider "yandex" {
  #token                    = "auth_token_here"
  service_account_key_file = "/root/regional-k8s-account-key.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone_name
}

#resource "yandex_kubernetes_cluster" "k8s-zonal" {
#  name = "k8s-zonal"
#  network_id = yandex_vpc_network.mynet.id
#  master {
#    master_location {
#      zone      = yandex_vpc_subnet.mysubnet.zone
#      subnet_id = yandex_vpc_subnet.mysubnet.id
#    }
#    security_group_ids = [yandex_vpc_security_group.k8s-public-services.id]
#  }
#  service_account_id      = yandex_iam_service_account.myaccount.id
#  node_service_account_id = yandex_iam_service_account.myaccount.id
#  depends_on = [
#    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
#    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
#    yandex_resourcemanager_folder_iam_member.images-puller,
#    yandex_resourcemanager_folder_iam_member.encrypterDecrypter
#  ]
#  kms_provider {
#    key_id = yandex_kms_symmetric_key.kms-key.id
#  }
#}

resource "yandex_vpc_network" "mynet" {
  name = "mynet"
}

resource "yandex_vpc_subnet" "mysubnet" {
  name = "mysubnet"
  v4_cidr_blocks = ["10.1.0.0/16"]
  zone           = var.zone_name
  network_id     = yandex_vpc_network.mynet.id
}

#resource "yandex_iam_service_account" "myaccount" {
#  name        = "zonal-k8s-account"
#  description = "K8S zonal service account"
#}

#resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
#  # Сервисному аккаунту назначается роль "k8s.clusters.agent".
#  folder_id = var.folder_id
#  role      = "k8s.clusters.agent"
#  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
#}
#
#resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
#  # Сервисному аккаунту назначается роль "vpc.publicAdmin".
#  folder_id = var.folder_id
#  role      = "vpc.publicAdmin"
#  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
#}
#
#resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
#  # Сервисному аккаунту назначается роль "container-registry.images.puller".
#  folder_id = var.folder_id
#  role      = "container-registry.images.puller"
#  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
#}
#
#resource "yandex_resourcemanager_folder_iam_member" "encrypterDecrypter" {
#  # Сервисному аккаунту назначается роль "kms.keys.encrypterDecrypter".
#  folder_id = var.folder_id
#  role      = "kms.keys.encrypterDecrypter"
#  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
#}
#
#resource "yandex_kms_symmetric_key" "kms-key" {
#  # Ключ Yandex Key Management Service для шифрования важной информации, такой как пароли, OAuth-токены и SSH-ключи.
#  name              = "kms-key"
#  default_algorithm = "AES_128"
#  rotation_period   = "8760h" # 1 год.
#}

resource "yandex_vpc_security_group" "k8s-public-services" {
  name        = "k8s-public-services"
  description = "Правила группы разрешают подключение к сервисам из интернета. Примените правила только для групп узлов."
  network_id  = yandex_vpc_network.mynet.id
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает проверки доступности с диапазона адресов балансировщика нагрузки. Нужно для работы отказоустойчивого кластера Managed Service for Kubernetes и сервисов балансировщика."
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие мастер-узел и узел-узел внутри группы безопасности."
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие под-под и сервис-сервис. Укажите подсети вашего кластера Managed Service for Kubernetes и сервисов."
    v4_cidr_blocks    = concat(yandex_vpc_subnet.mysubnet.v4_cidr_blocks)
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ICMP"
    description       = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks    = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавьте или измените порты на нужные вам."
    v4_cidr_blocks    = ["0.0.0.0/0"]
    from_port         = 30000
    to_port           = 32767
  }
  egress {
    protocol          = "ANY"
    description       = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Yandex Object Storage, Docker Hub и т. д."
    v4_cidr_blocks    = ["0.0.0.0/0"]
    from_port         = 0
    to_port           = 65535
  }
}

# Compute instance group for masters

resource "yandex_compute_instance_group" "k8s-masters" {
  name               = "k8s-masters"
  service_account_id = var.service_account_id
  depends_on = [
    yandex_vpc_network.mynet,
    yandex_vpc_subnet.mysubnet,
  ]

  # Шаблон экземпляра, к которому принадлежит группа экземпляров.
  instance_template {

    # Имя виртуальных машин, создаваемых Instance Groups
    name = "master-{instance.index}"

    # Ресурсы, которые будут выделены для создания виртуальных машин в Instance Groups
    resources {
      cores  = 2
      memory = 2
      core_fraction = 20 # Базовый уровень производительности vCPU. https://cloud.yandex.ru/docs/compute/concepts/performance-levels
    }

    # Загрузочный диск в виртуальных машинах в Instance Groups
    boot_disk {
      initialize_params {
        image_id = "fd864gbboths76r8gm5f" # ubuntu-2204-lts
        size     = 10
        type     = "network-ssd"
      }
    }

    network_interface {
      network_id = yandex_vpc_network.mynet.id
      subnet_ids = [
        yandex_vpc_subnet.mysubnet.id,
      ]
      # Флаг nat true указывает что виртуалкам будет предоставлен публичный IP адрес.
      nat = true
    }

    metadata = {
      ssh-keys = "${var.vm_user}:${file("${var.ssh_key_path}")}"
    }
    network_settings {
      type = "STANDARD"
    }
  }
  # Группа с необходимым количеством ВМ в рамках доступных
  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    zones = [
      var.zone_name,
    ]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1 # Максимальное количество одновременно запускаемых ВМ
    max_expansion   = 1
    max_deleting    = 1
  }
}

# Compute instance group for workers

resource "yandex_compute_instance_group" "k8s-workers" {
  name               = "k8s-workers"
  service_account_id = var.service_account_id
  depends_on = [
    yandex_vpc_network.mynet,
    yandex_vpc_subnet.mysubnet,
  ]

  instance_template {

    name = "worker-{instance.index}"

    resources {
      cores  = 2
      memory = 2
      core_fraction = 20
    }

    boot_disk {
      initialize_params {
        image_id = "fd864gbboths76r8gm5f" # ubuntu-2204-lts
        size     = 10
        type     = "network-hdd"
      }
    }

    network_interface {
      network_id = yandex_vpc_network.mynet.id
      subnet_ids = [
        yandex_vpc_subnet.mysubnet.id,
      ]
      # Флаг nat true указывает что виртуалкам будет предоставлен публичный IP адрес.
      nat = true
    }

    metadata = {
      ssh-keys = "${var.vm_user}:${file("${var.ssh_key_path}")}"
    }
    network_settings {
      type = "STANDARD"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    zones = [
      var.zone_name,
    ]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }
}
