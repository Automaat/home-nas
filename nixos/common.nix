{ config, pkgs, ... }:

{
  # NixOS version
  system.stateVersion = "25.05";

  # Bootloader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Locale
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Networking
  networking.firewall.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Base packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    btop
    tmux
    curl
    wget
    rsync
    ncdu
    iotop
    lsof
    pciutils
    usbutils
    nfs-utils
  ];

  # Users
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJx8wg+9mULtkH3ZgSIoF/GWaIIUNHslkWeo0bukAwuT skalskimarcin33@gmail.com"
  ];

  # Sops secrets
  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # Automatic updates
  system.autoUpgrade = {
    enable = false;  # Manual control preferred
  };

  # Nix settings
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Security
  security.sudo.wheelNeedsPassword = false;
}
