# Home NAS Infrastructure

NixOS + Proxmox-based home NAS with media services, managed via Infrastructure as Code.

## Architecture

- **Proxmox Host**: AOOSTAR WTR MAX (AMD R7 Pro 8845HS)
  - ZFS pools: tank-vms (NVMe), tank-media (RAIDZ1)
  - GPU passthrough: AMD 780M iGPU → media-services VM

- **VMs**:
  - media-services (NixOS): Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent
  - infrastructure (NixOS): Caddy reverse proxy
  - custom-workloads (Ubuntu): User-defined Docker containers

## Setup

### Prerequisites

- Nix with flakes enabled
- OpenTofu
- Ansible
- sops + age

### Initial Deployment

1. **Bootstrap Proxmox**:

   ```bash
   # Already done - see plan.md
   ```

2. **Create VM templates** (manual for now):

   - NixOS template
   - Ubuntu template

3. **Deploy infrastructure**:

   ```bash
   cd terraform
   tofu init
   tofu plan
   tofu apply
   ```

4. **Deploy NixOS VMs**:

   ```bash
   nixos-rebuild switch \
     --flake .#media-services \
     --target-host root@media-services \
     --build-host localhost

   nixos-rebuild switch \
     --flake .#infrastructure \
     --target-host root@infrastructure \
     --build-host localhost
   ```

5. **Deploy Ubuntu containers**:

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
   ```

## Secrets Management

Secrets are encrypted with sops-nix using age encryption:

```bash
# Edit secrets
sops nixos/secrets/secrets.yaml

# Decrypt to view
sops -d nixos/secrets/secrets.yaml
```

Age key is derived from Proxmox SSH host key and stored in VMs at `/var/lib/sops-nix/key.txt`.

## Maintenance

- Renovate creates PRs for dependency updates
- GitHub Actions validates changes on PRs
- Manual deployment via nixos-rebuild and ansible-playbook

## Storage Layout

- `/tank-vms`: NVMe pool for VM disks + Mac workspace (NFS)
- `/tank-media`: HDD RAIDZ1 for media storage
  - `/data/media/{movies,tv,music}`: Media libraries
  - `/data/downloads/{complete,incomplete}`: Download staging

## Network

- Proxmox host: 192.168.0.101
- media-services: 192.168.0.102
- infrastructure: 192.168.0.103
- custom-workloads: 192.168.0.104
