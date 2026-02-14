# Storage Configuration
#
# NFS shares from ZFS datasets for VM access
# Configured via Ansible playbook: ansible/playbooks/configure-proxmox.yml

# Note: The Telmate Proxmox provider doesn't support NFS share configuration
# Use Ansible to configure Proxmox host storage

# Run Ansible playbook to configure NFS:
# cd ../ansible && ansible-playbook -i inventory.yml playbooks/configure-proxmox.yml

# Output Ansible command
output "ansible_storage_setup" {
  description = "Ansible command to configure storage on Proxmox host"
  value = <<-EOT
    cd ../ansible && ansible-playbook -i inventory.yml playbooks/configure-proxmox.yml
  EOT
}

# Output storage info
output "nfs_shares" {
  description = "NFS shares configured via Ansible"
  value = {
    mac_workspace = {
      path        = "/tank-vms/mac-workspace"
      description = "Mac 10GbE workspace storage (NVMe-backed)"
      access      = "192.168.0.0/24"
    }
    media_data = {
      path        = "/tank-media/data"
      description = "Media storage for VMs (HDD RAIDZ1)"
      access      = "192.168.0.0/24"
    }
  }
}
