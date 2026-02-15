# Home NAS Infrastructure

Proxmox-based home NAS with media services, managed via Infrastructure as Code.

## Architecture

- **Proxmox Host**: AOOSTAR WTR MAX (AMD R7 Pro 8845HS)
  - ZFS pools: tank-vms (NVMe), tank-media (RAIDZ1)
  - GPU passthrough: AMD 780M iGPU → media-services VM

- **VMs**:
  - media-services (Ubuntu): Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent
  - infrastructure (Ubuntu): Caddy reverse proxy
  - custom-workloads (Ubuntu): User-defined Docker containers

## Setup

### Prerequisites

- OpenTofu
- Ansible
- sops + age

### Initial Deployment

1. **Bootstrap Proxmox**:

   ```bash
   # Already done - see plan.md
   ```

2. **Create VM template**:

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbooks/create-ubuntu-cloud-template.yml
   ```

3. **Deploy infrastructure**:

   ```bash
   cd terraform
   tofu init
   tofu plan
   tofu apply
   ```

4. **Deploy containers**:

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
   ```

## Secrets Management

Secrets are encrypted with sops using age encryption:

```bash
# Edit secrets
sops ansible/secrets/secrets.yaml

# Decrypt to view
sops -d ansible/secrets/secrets.yaml
```

Age key is derived from Proxmox SSH host key.

## Maintenance

- Renovate creates PRs for dependency updates
- GitHub Actions validates changes on PRs
- Manual deployment via ansible-playbook

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
