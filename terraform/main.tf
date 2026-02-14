terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://192.168.0.101:8006/api2/json"
  pm_tls_insecure = true
  # Use environment variables for credentials:
  # PM_API_TOKEN_ID and PM_API_TOKEN_SECRET
}

# Media Services VM
resource "proxmox_vm_qemu" "media_services" {
  name        = "media-services"
  target_node = "pve"
  clone       = "nixos-template"  # Create this template first

  cores   = 4
  sockets = 1
  memory  = 8192

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
  target_node = "pve"
  clone       = "nixos-template"

  cores   = 2
  sockets = 1
  memory  = 2048

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
  target_node = "pve"
  clone       = "ubuntu-template"  # Create this template first

  cores   = 4
  sockets = 1
  memory  = 8192

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
