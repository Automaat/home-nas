terraform {
  required_version = ">= 1.9.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.95"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true
  username = var.proxmox_username
  password = var.proxmox_password
}

# Infrastructure VM
resource "proxmox_virtual_environment_vm" "infrastructure" {
  name      = "infrastructure"
  node_name = var.proxmox_node
  on_boot   = true
  vm_id     = 101

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
