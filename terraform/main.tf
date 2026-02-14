terraform {
  required_version = ">= 1.9.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.71"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true
  username = var.proxmox_username
  password = var.proxmox_password
}

# Media Services VM
resource "proxmox_virtual_environment_vm" "media_services" {
  name      = "media-services"
  node_name = var.proxmox_node
  on_boot   = true
  vm_id     = 100
  machine   = "q35"

  clone {
    vm_id = 9001 # ubuntu-template
  }

  cpu {
    cores = var.media_services_cores
  }

  memory {
    dedicated = var.media_services_memory
  }

  agent {
    enabled = true
  }

  # Services network (VLAN 20)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 20
  }

  # Downloads network (VLAN 40 - qBittorrent)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 40
  }

  # GPU passthrough (AMD 780M iGPU)
  hostpci {
    device = "hostpci0"
    id     = "0000:01:00.0"
    pcie   = true
    rombar = true
  }

  disk {
    datastore_id = "tank-vms"
    interface    = "scsi0"
    size         = 32
  }
}

# Infrastructure VM
resource "proxmox_virtual_environment_vm" "infrastructure" {
  name      = "infrastructure"
  node_name = var.proxmox_node
  on_boot   = true
  vm_id     = 101

  clone {
    vm_id = 9001 # ubuntu-template
  }

  cpu {
    cores = var.infrastructure_cores
  }

  memory {
    dedicated = var.infrastructure_memory
  }

  agent {
    enabled = true
  }

  # Management network (VLAN 10)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 10
  }

  # Public network (VLAN 30 - Caddy external access)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 30
  }

  disk {
    datastore_id = "tank-vms"
    interface    = "scsi0"
    size         = 16
  }
}

# Custom Workloads VM
resource "proxmox_virtual_environment_vm" "custom_workloads" {
  name      = "custom-workloads"
  node_name = var.proxmox_node
  on_boot   = true
  vm_id     = 102

  clone {
    vm_id = 9001 # ubuntu-template
  }

  cpu {
    cores = var.custom_workloads_cores
  }

  memory {
    dedicated = var.custom_workloads_memory
  }

  agent {
    enabled = true
  }

  # Services network (VLAN 20)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 20
  }

  disk {
    datastore_id = "tank-vms"
    interface    = "scsi0"
    size         = 64
  }
}
