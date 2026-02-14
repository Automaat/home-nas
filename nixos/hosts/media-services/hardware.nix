{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Bootloader
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Swap
  swapDevices = [ ];

  # GPU passthrough (AMD iGPU)
  # The GPU is passed through via Proxmox hostpci
  # Enable DRI for hardware acceleration
  hardware.graphics.enable = true;

  # Add mesa drivers for AMD GPU
  hardware.graphics.extraPackages = with pkgs; [
    mesa
    mesa.drivers
  ];
}
