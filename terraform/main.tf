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

# Media Services VM - Ubuntu UEFI with GPU Passthrough
resource "proxmox_virtual_environment_vm" "media_services" {
  name      = "media-services"
  node_name = var.proxmox_node
  on_boot   = true
  vm_id     = 100
  machine   = "q35"

  # UEFI BIOS required for GPU ROM files
  bios = "ovmf"

  cpu {
    cores = 6
    type  = "host"
  }

  memory {
    dedicated = 16384
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

  # Downloads network (VLAN 40)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 40
  }

  # GPU passthrough (AMD 780M iGPU)
  hostpci {
    device   = "hostpci0"
    id       = "0000:01:00.0"
    pcie     = true
    rom_file = "vbios_8845hs.bin"
  }

  # Audio device (required for UEFI GPU passthrough)
  hostpci {
    device   = "hostpci1"
    id       = "0000:01:00.1"
    pcie     = true
    rom_file = "AMDGopDriver_8845hs.rom"
  }

  # EFI disk
  efi_disk {
    datastore_id      = "tank-vms"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = true
  }

  # System disk
  disk {
    datastore_id = "tank-vms"
    interface    = "scsi0"
    size         = 64
    file_format  = "raw"
  }

  # Cloud-init drive
  cdrom {
    enabled   = true
    file_id   = "tank-vms:cloudinit"
    interface = "ide2"
  }

  # Cloud-init configuration
  initialization {
    datastore_id = "tank-vms"

    user_account {
      username = "root"
      password = var.vm_default_password
      keys     = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # Vendor data for automated setup
    vendor_data_file_id = "local:snippets/vendor.yaml"
  }

  # Hide virtualization from guest (required for GPU drivers)
  kvm_arguments = "-cpu host,kvm=off,-hypervisor"

  # Lifecycle management
  lifecycle {
    ignore_changes = [
      # Ignore cloud-init changes after first boot
      initialization[0].user_account[0].password,
    ]
  }
}

output "media_services_info" {
  value = {
    vm_id   = proxmox_virtual_environment_vm.media_services.vm_id
    name    = proxmox_virtual_environment_vm.media_services.name
    message = "VM will auto-install guest agent and GPU drivers on first boot"
  }
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
