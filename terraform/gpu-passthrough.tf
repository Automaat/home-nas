# GPU Passthrough Configuration

# AMD 780M iGPU passthrough to media-services VM
# PCI address verification: lspci | grep -E 'VGA|Display'
# IOMMU group check: find /sys/kernel/iommu_groups/ -type l

# Prerequisites configured on Proxmox host:
# 1. GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt video=efifb:off"
# 2. /etc/modprobe.d/vfio.conf:
#    options vfio-pci ids=1002:1900
#    softdep amdgpu pre: vfio-pci
# 3. update-grub && update-initramfs -u && reboot
# 4. Verify: lspci -nnk | grep -A 3 -E 'VGA|Display' (should show vfio-pci driver)

# Note: GPU passthrough configured in main.tf via hostpci block
# media-services VM: hostpci0 = 0000:01:00.0 (AMD 780M iGPU)

# eGPU Configuration (optional, if AOOSTAR AG01 dock connected):
# custom-workloads VM would get eGPU via hostpci
# Example:
# hostpci {
#   host   = "0000:02:00.0"  # Verify actual PCIe address
#   pcie   = 1
#   rombar = 1
# }

# IMPORTANT: eGPU hot-swap warnings
# - Never disconnect eGPU while VM is running
# - Shutdown VM before disconnecting OCuLink cable
# - PCIe address may change after reconnection (verify with lspci)
