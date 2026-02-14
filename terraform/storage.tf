# NFS Storage Configuration
# tank-media is managed directly on Proxmox host via ZFS
# This file documents NFS exports configured on the Proxmox host

# NFS export for media-services VM
# Configured on Proxmox host:
# zfs set sharenfs="rw=@192.168.0.0/24,no_subtree_check" tank-media/data

# NFS export for Mac workspace over 10GbE
# Configured on Proxmox host:
# zfs set sharenfs="rw=@192.168.0.0/24,no_root_squash" tank-vms/mac-workspace

# Note: Proxmox NFS server runs on host, not managed by Terraform
# VMs mount these via /etc/fstab or systemd.mount units
