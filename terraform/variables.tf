variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://192.168.0.101:8006"
}

variable "proxmox_username" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "media_services_cores" {
  description = "Number of CPU cores for media-services VM"
  type        = number
  default     = 6
}

variable "media_services_memory" {
  description = "Memory in MB for media-services VM"
  type        = number
  default     = 20480
}

variable "infrastructure_cores" {
  description = "Number of CPU cores for infrastructure VM"
  type        = number
  default     = 2
}

variable "infrastructure_memory" {
  description = "Memory in MB for infrastructure VM"
  type        = number
  default     = 4096
}

variable "custom_workloads_cores" {
  description = "Number of CPU cores for custom-workloads VM"
  type        = number
  default     = 4
}

variable "custom_workloads_memory" {
  description = "Memory in MB for custom-workloads VM"
  type        = number
  default     = 28672
}

variable "vm_default_password" {
  description = "Default password for cloud-init VMs"
  type        = string
  sensitive   = true
  default     = ""
}
