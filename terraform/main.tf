terraform {
  required_version = ">= 1.9.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_tls_insecure = true
  # Use environment variables for credentials:
  # PM_API_TOKEN_ID and PM_API_TOKEN_SECRET
}

# Media Services VM
resource "proxmox_vm_qemu" "media_services" {
  name        = "media-services"
  target_node = var.proxmox_node
  clone       = "nixos-template" # Create this template first

  cores   = var.media_services_cores
  sockets = 1
  memory  = var.media_services_memory

  disk {
    storage = "local-lvm"
    type    = "scsi"
    size    = "32G"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # GPU passthrough (AMD 780M iGPU)
  hostpci {
    host    = "0000:01:00.0"
    pcie    = true
    rombar  = true
    x-vga   = true
  }

  onboot = true
  agent  = 1
}

# Infrastructure VM
resource "proxmox_vm_qemu" "infrastructure" {
  name        = "infrastructure"
  target_node = var.proxmox_node
  clone       = "nixos-template"

  cores   = var.infrastructure_cores
  sockets = 1
  memory  = var.infrastructure_memory

  disk {
    storage = "local-lvm"
    type    = "scsi"
    size    = "16G"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  onboot = true
  agent  = 1
}

# Custom Workloads VM (Ubuntu)
resource "proxmox_vm_qemu" "custom_workloads" {
  name        = "custom-workloads"
  target_node = var.proxmox_node
  clone       = "ubuntu-template" # Create this template first

  cores   = var.custom_workloads_cores
  sockets = 1
  memory  = var.custom_workloads_memory

  disk {
    storage = "local-lvm"
    type    = "scsi"
    size    = "64G"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  onboot = true
  agent  = 1
}
