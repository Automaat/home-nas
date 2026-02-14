# Network Configuration
# VLANs to be configured on Proxmox host

# VLAN Configuration (manual setup on Proxmox):
# - VLAN 10 (Management): Proxmox host, infrastructure VM
# - VLAN 20 (Services): media-services VM, internal service communication
# - VLAN 30 (Public): infrastructure VM public-facing interface
# - VLAN 40 (Downloads): media-services VM qBittorrent isolation

# Current simplified setup (single bridge, will migrate to VLANs):
# All VMs on vmbr0 (192.168.0.0/24)
# - Proxmox host: 192.168.0.101
# - media-services: 192.168.0.102
# - infrastructure: 192.168.0.103
# - custom-workloads: 192.168.0.104

# Future VLAN setup (to implement):
# resource "null_resource" "configure_vlans" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       ssh root@${var.proxmox_api_url} <<'EOF'
#       # Create VLAN-aware bridge
#       cat >> /etc/network/interfaces <<'IFACE'
#       auto vmbr0
#       iface vmbr0 inet static
#         address 192.168.0.101/24
#         bridge-ports eno1
#         bridge-stp off
#         bridge-fd 0
#         bridge-vlan-aware yes
#         bridge-vids 10 20 30 40
#       IFACE
#
#       systemctl restart networking
#       EOF
#     EOT
#   }
# }

# VM VLAN assignments (when enabled):
# media-services: VLAN 20 (services), VLAN 40 (downloads)
# infrastructure: VLAN 10 (management), VLAN 30 (public)
# custom-workloads: VLAN 20 (services)
