terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Rede para o cluster
resource "libvirt_network" "k8s_network" {
  name      = "k8s-network"
  mode      = "nat"
  addresses = ["10.17.3.0/24"]
  autostart = true
  
  dns {
    enabled = true
  }
}

# Volume base da imagem Ubuntu
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-base.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

# Cloud-init disk for control plane
resource "libvirt_cloudinit_disk" "controlplane_init" {
  name      = "controlplane-init.iso"
  pool      = "default"
  user_data = templatefile("${path.module}/cloud-init.yaml", { hostname = "controlplane", ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path))) })
}

# Cloud-init disk for workers
resource "libvirt_cloudinit_disk" "worker_init" {
  count     = 2
  name      = "worker-${count.index + 1}-init.iso"
  pool      = "default"
  user_data = templatefile("${path.module}/cloud-init.yaml", { hostname = "worker-${count.index + 1}", ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path))) })
}

# Volume do control plane
resource "libvirt_volume" "controlplane" {
  name           = "k8s-controlplane.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 21474836480 # 20GB
}

# Volumes dos workers
resource "libvirt_volume" "worker" {
  count          = 2
  name           = "k8s-worker-${count.index + 1}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 21474836480 # 20GB
}

# VM Control Plane
resource "libvirt_domain" "controlplane" {
  name   = "k8s-controlplane"
  memory = "4096"
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.controlplane_init.id

  network_interface {
    network_id     = libvirt_network.k8s_network.id
    hostname       = "controlplane"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.controlplane.id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# VMs Workers
resource "libvirt_domain" "worker" {
  count  = 2
  name   = "k8s-worker-${count.index + 1}"
  memory = "2048"
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.worker_init[count.index].id

  network_interface {
    network_id     = libvirt_network.k8s_network.id
    hostname       = "worker-${count.index + 1}"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.worker[count.index].id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# Gerar inventário Ansible
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    controlplane_ip = libvirt_domain.controlplane.network_interface[0].addresses[0]
    worker_ips      = [for w in libvirt_domain.worker : w.network_interface[0].addresses[0]]
  })
  filename = "${path.module}/../ansible/inventory.ini"
}

variable "ssh_public_key_path" {
  description = "Chave pública SSH injetada nas VMs pelo cloud-init"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
