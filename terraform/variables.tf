variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://192.168.0.101:8006/api2/json"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "media_services_cores" {
  description = "Number of CPU cores for media-services VM"
  type        = number
  default     = 4
}

variable "media_services_memory" {
  description = "Memory in MB for media-services VM"
  type        = number
  default     = 8192
}

variable "infrastructure_cores" {
  description = "Number of CPU cores for infrastructure VM"
  type        = number
  default     = 2
}

variable "infrastructure_memory" {
  description = "Memory in MB for infrastructure VM"
  type        = number
  default     = 2048
}

variable "custom_workloads_cores" {
  description = "Number of CPU cores for custom-workloads VM"
  type        = number
  default     = 4
}

variable "custom_workloads_memory" {
  description = "Memory in MB for custom-workloads VM"
  type        = number
  default     = 8192
}
