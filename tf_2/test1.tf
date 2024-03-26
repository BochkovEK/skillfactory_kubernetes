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
  service_account_key_file = "/root/admin.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone_name
}

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  name = "k8s-cluster"
  network_id = yandex_vpc_network.mynet.id
  master {
    master_location {
      zone      = yandex_vpc_subnet.mysubnet.zone
      subnet_id = yandex_vpc_subnet.mysubnet.id
    }

    public_ip = true

    security_group_ids = [yandex_vpc_security_group.k8s-public-services.id, yandex_vpc_security_group.k8s-nodes-ssh-access.id]
  }
  service_account_id      = yandex_iam_service_account.myaccount.id
  node_service_account_id = yandex_iam_service_account.myaccount.id
  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
    yandex_resourcemanager_folder_iam_member.images-puller,
    yandex_resourcemanager_folder_iam_binding.editor,
    yandex_resourcemanager_folder_iam_binding.images-pusher,
    yandex_resourcemanager_folder_iam_member.encrypterDecrypter
  ]
  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

resource "yandex_vpc_network" "mynet" {
  name = "mynet"
}

resource "yandex_vpc_subnet" "mysubnet" {
  name = "mysubnet"
  v4_cidr_blocks = ["10.1.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mynet.id
}

resource "yandex_iam_service_account" "myaccount" {
  name        = "zonal-k8s-account"
  description = "K8S zonal service account"
}

# Assign "editor" role to Kubernetes service account
resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = var.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${var.service_account_id}"
  ]
}

# Assign "container-registry.images.pusher" role to Kubernetes service account
resource "yandex_resourcemanager_folder_iam_binding" "images-pusher" {
  folder_id = var.folder_id
  role      = "container-registry.images.pusher"
  members = [
    "serviceAccount:${var.service_account_id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
  # Сервисному аккаунту назначается роль "k8s.clusters.agent".
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
  # Сервисному аккаунту назначается роль "vpc.publicAdmin".
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  # Сервисному аккаунту назначается роль "container-registry.images.puller".
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "encrypterDecrypter" {
  # Сервисному аккаунту назначается роль "kms.keys.encrypterDecrypter".
  folder_id = var.folder_id
  role      = "kms.keys.encrypterDecrypter"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_kms_symmetric_key" "kms-key" {
  # Ключ Yandex Key Management Service для шифрования важной информации, такой как пароли, OAuth-токены и SSH-ключи.
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 1 год.
}

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
    protocol       = "ANY"
    description    = "Правило разрешает взаимодействие под-под и сервис-сервис. Укажите подсети вашего кластера Managed Service for Kubernetes и сервисов."
    v4_cidr_blocks = concat(yandex_vpc_subnet.mysubnet.v4_cidr_blocks)
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "ICMP"
    description    = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавьте или измените порты на нужные вам."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Yandex Object Storage, Docker Hub и т. д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    description    = "The rule allows connection to Kubernetes API on 6443 port from specified network."
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }
  ingress {
    description    = "The rule allows connection to Kubernetes API on 443 port from specified network."
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
}

resource "yandex_vpc_default_security_group" "default-sg" {
  description = "Default security group allows connections to Managed Service for GitLab"
  network_id  = yandex_vpc_network.mynet.id

  ingress {
    description    = "The rule allows connection to Git repository by SSH on 22 port from the Internet"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    description    = "The rule allows connection to Git repository by SSH on 2222 port from the Internet"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 2222
  }

  ingress {
    description    = "The rule allows HTTP connections from the Internet"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    description    = "The rule allows HTTPS connections from the Internet"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    description    = "The rule allows connection to Yandex Container Registry on 5050 port"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5050
  }
}

resource "yandex_vpc_security_group" "k8s-nodes-ssh-access" {
  name        = "k8s-nodes-ssh-access"
  description = "Group rules allow connections to cluster nodes over SSH. Apply the rules only for node groups."
  network_id  = yandex_vpc_network.mynet.id

  ingress {
    protocol       = "TCP"
    description    = "Rule allows connections to nodes over SSH from specified IPs."
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
}

resource "yandex_kubernetes_node_group" "k8s-node-group" {
  description = "Node group for Managed Service for Kubernetes cluster"
  name        = "k8s-node-group"
  cluster_id  = yandex_kubernetes_cluster.k8s-cluster.id
  version     = var.k8s_version

  scale_policy {
    fixed_scale {
      size = 2 # Number of hosts
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.mysubnet.id]
      security_group_ids = [yandex_vpc_security_group.k8s-public-services.id, yandex_vpc_security_group.k8s-nodes-ssh-access.id]
    }

    resources {
      memory = 4 # RAM quantity in GB
      cores  = 4 # Number of CPU cores
    }

    boot_disk {
      type = "network-hdd"
      size = 64 # Disk size in GB
    }

#    Ключ user-dataне поддерживает передачу пользовательских данных. Параметры для ssh-подключений необходимо указать в ssh-keysключе метаданных ВМ.
    metadata = {
      ssh-keys = "${var.vm_user}:${file("${var.ssh_key_path}")}"
    }
}

# Container Registry
resource "yandex_container_registry" "container-registry" {
  name      = var.registry_name
  folder_id = var.folder_id
}

resource  "yandex_iam_service_account_key" "sa-auth-key" {
  description        = "Authorized key for service accaunt"
  service_account_id = yandex_iam_service_account.myaccount.id
}

# Local file with authorized key data
resource "local_sensitive_file" "key-json" {
  depends_on = [
    yandex_iam_service_account_key.sa-auth-key,
    ]
 content = jsonencode({
    "id" : "${yandex_iam_service_account_key.sa-auth-key.id}",
    "service_account_id" : "${yandex_iam_service_account.k8s-sa.id}",
    "created_at" : "${yandex_iam_service_account_key.sa-auth-key.created_at}",
    "key_algorithm" : "${yandex_iam_service_account_key.sa-auth-key.key_algorithm}",
    "public_key" : "${yandex_iam_service_account_key.sa-auth-key.public_key}",
    "private_key" : "${yandex_iam_service_account_key.sa-auth-key.private_key}"
  })
  filename = "key.json"
}
}


