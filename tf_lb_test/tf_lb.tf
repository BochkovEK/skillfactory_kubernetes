# Infrastructure for Yandex Cloud Managed Service for Kubernetes cluster
#
# RU: https://cloud.yandex.ru/docs/managed-kubernetes/operations/create-load-balancer
# EN: https://cloud.yandex.com/en/docs/managed-kubernetes/operations/create-load-balancer

# Set the configuration of the Managed Service for Kubernetes cluster:

locals {
  folder_id   = var.folder_id            # Set your cloud folder ID.
  k8s_version = var.k8s_version            # Set the Kubernetes version.
  sa_name     = "admin-lb-kuber"            # Set the service account name

  # The following settings are predefined. Change them only if necessary.
  network_name              = "k8s-network" # Name of the network
  subnet_name               = "subnet-a" # Name of the subnet
  zone_a_v4_cidr_blocks     = "10.1.0.0/16" # CIDR block for the subnet in the ru-central1-a availability zone
  main_security_group_name  = "k8s-main-sg" # Name of the main security group of the cluster
  public_services_sg_name   = "k8s-public-services" # Name of the public services security group for node groups
  k8s_cluster_name          = "k8s-cluster" # Name of the Kubernetes cluster
  k8s_node_group_name       = "k8s-node-group" # Name of the Kubernetes node group
}

resource "yandex_vpc_network" "k8s-network" {
  description = "Network for the Managed Service for Kubernetes cluster"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.k8s-network.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_security_group" "k8s-main-sg" {
  description = "Security group ensure the basic performance of the cluster. Apply it to the cluster and node groups."
  name        = local.main_security_group_name
  network_id  = yandex_vpc_network.k8s-network.id

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
    description       = "The rule allows availability checks from the load balancer's range of addresses. It is required for the operation of a fault-tolerant cluster and load balancer services."
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks" # The load balancer's address range.
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description       = "The rule allows the master-node and node-node interaction within the security group"
    protocol          = "ANY"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description    = "The rule allows the pod-pod and service-service interaction. Specify the subnets of your cluster and services."
    protocol       = "ANY"
    v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    description    = "The rule allows receipt of debugging ICMP packets from internal subnets"
    protocol       = "ICMP"
    v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
  }

  ingress {
    description    = "The rule allows connection to Kubernetes API on 6443 port from specified network"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }

  ingress {
    description    = "The rule allows connection to Kubernetes API on 443 port from specified network"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  egress {
    description    = "The rule allows all outgoing traffic. Nodes can connect to Yandex Container Registry, Object Storage, Docker Hub, and more."
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

   ingress {
    description    = "The rule allows incoming traffic from the internet to django app."
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 3000
    to_port        = 3500
  }
}

resource "yandex_vpc_security_group" "k8s-public-services" {
  description = "Security group allows connections to services from the internet. Apply the rules only for node groups."
  name        = local.public_services_sg_name
  network_id  = yandex_vpc_network.k8s-network.id

  ingress {
    description    = "The rule allows incoming traffic from the internet to the NodePort port range. Add ports or change existing ones to the required ports."
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 3000
    to_port        = 3500
  }

    ingress {
    description    = ""
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 8000
    to_port        = 9000
  }

  ingress {
    description    = ""
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 70
    to_port        = 90
  }
}

resource "yandex_iam_service_account" "k8s-sa" {
  description = "Service account for Kubernetes cluster"
  name        = local.sa_name
}

# Assign "editor" role to Kubernetes service account
resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = local.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

# Assign "container-registry.images.puller" role to Kubernetes service account
resource "yandex_resourcemanager_folder_iam_binding" "images-puller" {
  folder_id = local.folder_id
  role      = "container-registry.images.puller"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  description = "Managed Service for Kubernetes cluster"
  name        = local.k8s_cluster_name
  network_id  = yandex_vpc_network.k8s-network.id

  master {
    version = local.k8s_version
    master_location {
      zone      = yandex_vpc_subnet.subnet-a.zone
      subnet_id = yandex_vpc_subnet.subnet-a.id
    }

    public_ip = true

    security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]
  }
  service_account_id      = yandex_iam_service_account.k8s-sa.id # Cluster service account ID
  node_service_account_id = yandex_iam_service_account.k8s-sa.id # Node group service account ID
  depends_on = [
    yandex_resourcemanager_folder_iam_binding.editor,
    yandex_resourcemanager_folder_iam_binding.images-puller
  ]
}

resource "yandex_kubernetes_node_group" "k8s-node-group" {
  description = "Node group for the Managed Service for Kubernetes cluster"
  name        = local.k8s_node_group_name
  cluster_id  = yandex_kubernetes_cluster.k8s-cluster.id
  version     = local.k8s_version

  scale_policy {
    fixed_scale {
      size = 1 # Number of hosts
    }
  }

  allocation_policy {
    location {
      zone = yandex_vpc_subnet.subnet-a.zone
    }
  }

  instance_template {
    platform_id = "standard-v2" # Intel Cascade Lake

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.subnet-a.id]
      security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]
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
}

#resource "yandex_vpc_address" "loadbalancer-addr" {
#  name = "loadbalancer-addr"
#  external_ipv4_address {
#    zone_id = yandex_vpc_subnet.subnet-a.zone
#  }
#}

#resource "yandex_lb_target_group" "foo" {
#  name      = "my-target-group"
#  region_id = "ru-central1"
#
#  target {
#    subnet_id = yandex_vpc_subnet.subnet-a.id
#    address   = yandex_kubernetes_node_group.k8s-node-group.
#  }
#}

#resource "yandex_lb_network_load_balancer" "load_balancer" {
#  name = "my-network-load-balancer"
#
#  listener {
#    name = "my-http-listener"
#    port = 8080
#    external_address_spec {
#      ip_version = "ipv4"
#    }
#  }
#
#   listener {
#    name = "my-django-listener"
#    port = 3003
#    external_address_spec {
#      ip_version = "ipv4"
#    }
#  }
#
#  attached_target_group {
#    target_group_id = yandex_kubernetes_node_group.k8s-node-group.id
#
#    healthcheck {
#      name = "http"
#      http_options {
#        port = 8080
#        path = "/ping"
#      }
#    }
#  }
#}