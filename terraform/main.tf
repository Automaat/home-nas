terraform {
  required_version = ">= 1.9.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true
  username = var.proxmox_username
  password = var.proxmox_password
}

# Infrastructure VM removed (migrated to LXC 101)

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

# Desktop VM - Ubuntu with GNOME + xRDP for remote desktop
resource "proxmox_virtual_environment_vm" "desktop" {
  name      = "desktop"
  node_name = var.proxmox_node
  on_boot   = true
  vm_id     = 103

  clone {
    vm_id = 9001 # ubuntu-template
  }

  cpu {
    cores = var.desktop_cores
    type  = "host"
  }

  memory {
    dedicated = var.desktop_memory
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

  initialization {
    datastore_id = "tank-vms"
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "192.168.20.107/24"
        gateway = "192.168.20.1"
      }
    }

    user_account {
      keys     = [var.ssh_public_key]
      username = "root"
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}
