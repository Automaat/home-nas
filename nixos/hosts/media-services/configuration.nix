{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
  ];

  # Hostname
  networking.hostName = "media-services";

  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # NFS client for mounting Proxmox storage
  fileSystems."/data" = {
    device = "192.168.0.101:/tank-media/data";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
  };

  # Docker Compose services
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      jellyfin = {
        image = "jellyfin/jellyfin:10.11.6";
        ports = [ "8096:8096" ];
        volumes = [
          "/data/media:/media:ro"
          "jellyfin-config:/config"
          "jellyfin-cache:/cache"
        ];
        environment = {
          TZ = "UTC";
        };
        extraOptions = [
          "--device=/dev/dri:/dev/dri"  # GPU passthrough for transcoding
        ];
      };

      sonarr = {
        image = "lscr.io/linuxserver/sonarr:4.0.16.2944-ls303";
        ports = [ "8989:8989" ];
        volumes = [
          "sonarr-config:/config"
          "/data:/data"
        ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "UTC";
        };
      };

      radarr = {
        image = "lscr.io/linuxserver/radarr:6.0.4.10291-ls292";
        ports = [ "7878:7878" ];
        volumes = [
          "radarr-config:/config"
          "/data:/data"
        ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "UTC";
        };
      };

      prowlarr = {
        image = "lscr.io/linuxserver/prowlarr:2.3.0.5236-ls137";
        ports = [ "9696:9696" ];
        volumes = [
          "prowlarr-config:/config"
        ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "UTC";
        };
      };

      qbittorrent = {
        image = "lscr.io/linuxserver/qbittorrent:5.1.4-r2-ls440";
        ports = [
          "8080:8080"
          "6881:6881"
          "6881:6881/udp"
        ];
        volumes = [
          "qbittorrent-config:/config"
          "/data/downloads:/data/downloads"
        ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "UTC";
          WEBUI_PORT = "8080";
        };
      };
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 8096 8989 7878 9696 8080 6881 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
