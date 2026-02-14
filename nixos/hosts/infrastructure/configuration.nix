{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
  ];

  # Hostname
  networking.hostName = "infrastructure";

  # Caddy reverse proxy
  services.caddy = {
    enable = true;
    virtualHosts = {
      "jellyfin.example.com" = {
        extraConfig = ''
          reverse_proxy media-services:8096
        '';
      };
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
