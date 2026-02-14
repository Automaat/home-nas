# Home NAS Implementation Tasks

## Hardware Setup

### Storage Architecture Overview

**NVMe Tier (Fast):**
- Purpose: VMs, Mac workspace, metadata caching
- Options: 2×2TB (2TB usable) → upgradeable to 2×4TB (4TB usable)
- Performance: 3500 MB/s read, saturates 10GbE
- Use cases: VM disks, active projects, Jellyfin metadata, transcoding cache

**HDD Tier (Capacity):**
- Purpose: Media storage, downloads, archives
- Start: 3×24TB RAIDZ1 (~48TB usable)
- Expand: Up to 8×24TB RAIDZ3 (~120TB usable)
- Performance: 200-300 MB/s sequential, sufficient for video streaming

**Why This Design:**
- Speed where needed (VMs, Mac storage on NVMe)
- Capacity where needed (media on HDDs)
- 10GbE Mac access: 400-800 MB/s from NVMe pool
- Gradual HDD expansion as budget allows
- Optional NVMe special device for HDD metadata acceleration

### [x] Verify Hardware Compatibility (before purchase)

- [x] Confirm WTR MAX has OCuLink port or M.2 slot compatible with OCuLink adapter
- [x] Check AOOSTAR specs/forums for OCuLink support
- [x] Verify eGPU power requirements vs AG01's 400W PSU
- [x] Consider eGPU width/length vs AG01 dock dimensions

### [x] Purchase Hardware

**Initial Purchase:**

- [x] AOOSTAR WTR MAX (AMD R7 Pro 8845HS, 11 bays)
- [x] Boot: 4TB NVMe (Samsung 990 PRO PCIe Gen4)
- [x] Fast tier: 2×2TB NVMe (Samsung 990 PRO or similar)
  - Alternative: 2×4TB NVMe if budget allows
  - Alternative: 1×4TB NVMe (no redundancy initially, add mirror later)
- [x] Data: 3×24TB HDD (Seagate IronWolf Pro ST24000NT001)

**Gradual Expansion (buy as budget allows):**

- [ ] Drive #4: 1×24TB HDD
- [ ] Drive #5: 1×24TB HDD
- [ ] Drive #6: 1×24TB HDD
- [ ] Drive #7: 1×24TB HDD
- [ ] Drive #8: 1×24TB HDD
- [ ] Hot spare: 1×24TB HDD (optional)

**NVMe Upgrade Path (optional):**

- [ ] If started with 2×2TB: Upgrade to 2×4TB via `zpool replace` (see notes)
- [ ] If started with 1×4TB: Add second 4TB via `zpool attach` for mirror

**eGPU Expansion (optional):**

- [ ] AOOSTAR AG01 eGPU Dock (OCuLink, 400W PSU)
- [ ] Dedicated GPU for custom-workloads VM (NVIDIA/AMD)
- [ ] Verify WTR MAX has OCuLink port or compatible M.2 slot

### [x] Install Proxmox VE

**Note:** System reinstalled 2024-02-14 after network config issues. ZFS pools imported successfully.

- [x] Install Proxmox on NVMe boot drive (reinstalled)
- [x] Verify OpenZFS version: `zfs --version` (need 2.3+ for RAIDZ expansion) - v2.3.4
- [x] Enable IOMMU in BIOS (AMD-Vi) - already enabled
- [ ] Verify OCuLink connection (if using eGPU): `lspci | grep -i vga`
- [x] Check IOMMU groups: `find /sys/kernel/iommu_groups/ -type l | grep -E '(VGA|Display)'`
- [x] Edit `/etc/default/grub`:
  ```
  # Single GPU (iGPU only):
  GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt video=efifb:off"

  # Dual GPU (iGPU + eGPU, if different IOMMU groups need separation):
  GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction video=efifb:off"
  ```
- [x] Get GPU PCI IDs: `lspci -nn | grep -E 'VGA|Display'`
  - AMD 780M iGPU: `1002:1900` (actual)
  - eGPU: note actual PCI ID
- [x] Create `/etc/modprobe.d/vfio.conf`:

  ```
  # Single GPU (iGPU only):
  options vfio-pci ids=1002:1900
  softdep amdgpu pre: vfio-pci

  # Dual GPU (iGPU + eGPU):
  options vfio-pci ids=1002:1900,10de:XXXX  # Replace 10de:XXXX with actual eGPU ID
  softdep amdgpu pre: vfio-pci
  softdep nvidia pre: vfio-pci  # Add if NVIDIA eGPU
  ```

- [x] Run `update-grub && update-initramfs -u && reboot`
- [x] Verify IOMMU: `dmesg | grep -i iommu`
- [x] Verify vfio binding: `lspci -nnk | grep -A 3 -E 'VGA|Display'` (should show `vfio-pci` driver)

### [x] Create ZFS Pools

**Initial Setup (3 HDDs + 2 NVMe):**
- [x] Install 3×20TB HDDs in bays + 2 NVMe in M.2 slots
- [x] Verify NVMe devices: `ls -la /dev/disk/by-id/nvme-*`
- [x] Create VM pool (single 2TB NVMe (no redundancy)):
  ```bash
  zpool create -f tank-vms mirror \
    /dev/disk/by-id/nvme-Samsung_990_PRO_... \
    /dev/disk/by-id/nvme-Samsung_990_PRO_...
  ```
  Or single drive (no redundancy):
  ```bash
  zpool create -f tank-vms /dev/disk/by-id/nvme-Samsung_990_PRO_...
  ```
- [x] Create media pool (RAIDZ1, ~36TB usable):
  ```bash
  zpool create -f tank-media raidz1 \
    /dev/disk/by-id/ata-ST24000NT001-... \
    /dev/disk/by-id/ata-ST24000NT001-... \
    /dev/disk/by-id/ata-ST24000NT001-...
  zfs set compression=lz4 tank-media
  zfs set atime=off tank-media
  ```
- [x] Create datasets:
  ```bash
  zfs create tank-media/data
  zfs create tank-media/data/media
  zfs create tank-media/data/media/movies
  zfs create tank-media/data/media/tv
  zfs create tank-media/data/media/music
  zfs create tank-media/data/downloads
  zfs create tank-media/data/downloads/incomplete
  zfs create tank-media/data/downloads/complete
  ```
- [ ] Add NVMe special device for metadata/small files (optional but recommended):
  ```bash
  # Use portion of tank-vms or separate NVMe
  zpool add tank-media special mirror \
    /dev/disk/by-id/nvme-Samsung_990_PRO_...
  zfs set special_small_blocks=1M tank-media
  ```
  Note: Special device stores metadata + files <1MB on NVMe = faster browsing
- [x] Create Mac storage dataset (for NFS mount over 10GbE):
  ```bash
  zfs create tank-vms/mac-workspace
  zfs set compression=lz4 tank-vms/mac-workspace
  zfs set sharenfs="rw=@192.168.0.0/24,no_root_squash" tank-vms/mac-workspace
  ```

**Expand Pool (as drives purchased):**
- [ ] Add drive #4 (RAIDZ2, ~48TB usable, survives 2 failures):
  ```bash
  zpool attach tank-media raidz1-0 /dev/disk/by-id/ata-ST24000NT001-...
  zpool status  # monitor expansion progress
  ```
- [ ] Add drive #5 (RAIDZ3, ~48TB usable, survives 3 failures):
  ```bash
  zpool attach tank-media raidz2-0 /dev/disk/by-id/ata-ST24000NT001-...
  ```
- [ ] Add drive #6 (RAIDZ3, ~72TB usable):
  ```bash
  zpool attach tank-media raidz3-0 /dev/disk/by-id/ata-ST24000NT001-...
  ```
- [ ] Add drive #7 (RAIDZ3, ~96TB usable):
  ```bash
  zpool attach tank-media raidz3-0 /dev/disk/by-id/ata-ST24000NT001-...
  ```
- [ ] Add drive #8 (RAIDZ3, ~120TB usable):
  ```bash
  zpool attach tank-media raidz3-0 /dev/disk/by-id/ata-ST24000NT001-...
  ```

**Notes:**
- RAIDZ expansion requires OpenZFS 2.3+
- Pool stays online during expansion
- Old data retains original parity ratio (slightly less efficient than fresh pool)
- Monitor expansion: `zpool status -v`

**NVMe Upgrade Notes:**
- To upgrade 2×2TB → 2×4TB mirror:
  ```bash
  zpool replace tank-vms /dev/old-2tb /dev/new-4tb-1  # Resilver
  zpool replace tank-vms /dev/old-2tb /dev/new-4tb-2  # Resilver
  zpool online -e tank-vms /dev/new-4tb-1             # Expand
  zpool online -e tank-vms /dev/new-4tb-2
  ```
- To add mirror to single drive:
  ```bash
  zpool attach tank-vms /dev/existing-4tb /dev/new-4tb  # Creates mirror
  ```
- NVMe performance: 3500 MB/s read, 3000 MB/s write (saturates 10GbE at 1250 MB/s)

### [x] Configure Networking

**Implementation:** Gradual VLAN setup using Ansible, tested and verified.

- [x] Create VLAN 10 (Management)
- [x] Create VLAN 20 (Services)
- [x] Create VLAN 30 (Public)
- [x] Create VLAN 40 (Downloads)
- [x] Configure vmbr0 with VLAN tagging
- [SKIP] Configure Proxmox host firewall - will configure manually if needed

**Approach:** Used `ifreload` instead of full network restart, with automatic connectivity testing and rollback support. VLANs configured via `ansible/playbooks/configure-vlans-gradual.yml` with step-by-step execution.

**Verification:** Created test VM with VLAN 20 tag, confirmed bridge VLAN tagging working correctly.

## Local Development Setup

### [x] Update Environment Tooling
- [x] Add to `~/sideprojects/environment-as-code/modules/packages.nix`:
  - opentofu
  - age
  - sops
  - ansible
- [x] Run `darwin-rebuild switch --flake .`

### [x] Initialize Repository
- [x] Create `~/sideprojects/home-nas` directory
- [x] Initialize git: `git init`
- [x] Create base structure:
  ```bash
  mkdir -p terraform nixos/{hosts/{media-services,infrastructure},modules,secrets} \
           ansible/{playbooks,docker-compose} docs .github/workflows
  ```

### [x] Setup Secrets Management
- [x] Get Proxmox SSH host key: `ssh root@proxmox-ip cat /etc/ssh/ssh_host_ed25519_key.pub`
- [x] Generate age key: `nix-shell -p ssh-to-age --run 'echo "<pubkey>" | ssh-to-age'`
- [x] Create `nixos/secrets/.sops.yaml`:
  ```yaml
  keys:
    - &admin age1xxx...
  creation_rules:
    - path_regex: secrets/.*\.yaml$
      key_groups:
        - age:
            - *admin
  ```

- [x] Create `nixos/secrets/secrets.yaml` with:

  - jellyfin_api_key
  - sonarr_api_key
  - radarr_api_key
  - prowlarr_api_key
  - qbittorrent_password
- [x] Encrypt: `sops nixos/secrets/secrets.yaml`

## Infrastructure as Code

### [x] Create Flake Configuration

- [x] Create `flake.nix`:

  ```nix
  {
    inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      sops-nix.url = "github:Mic92/sops-nix";
    };
    outputs = { nixpkgs, sops-nix, ... }: {
      nixosConfigurations = {
        media-services = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/common.nix
            ./nixos/hosts/media-services/configuration.nix
          ];
        };
        infrastructure = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/common.nix
            ./nixos/hosts/infrastructure/configuration.nix
          ];
        };
      };
    };
  }
  ```
- [x] Run `nix flake update`

### [x] Create NixOS Common Config

- [x] Create `nixos/common.nix`:
  - Base packages
  - SSH config (keys from environment-as-code)
  - Firewall defaults
  - User accounts
  - Timezone, locale

### [x] Create Media Services VM Config
- [ ] Create `nixos/hosts/media-services/configuration.nix`
- [ ] Create `nixos/hosts/media-services/hardware.nix`:
  - GPU passthrough (vfio-pci)
  - NFS mount (/tank-media/data → /data)
- [ ] Create `nixos/hosts/media-services/docker-compose.nix`:
  - Enable Docker
  - Define Jellyfin container (with GPU device)
  - Define Arr stack containers
  - Define qBittorrent container
  - All use `/data` volumes

### [x] Create Infrastructure VM Config
- [ ] Create `nixos/hosts/infrastructure/configuration.nix`
- [ ] Create `nixos/hosts/infrastructure/caddy.nix`:
  - Caddy service config
  - Reverse proxy rules (jellyfin.yourdomain.com)
  - WebSocket support
  - Auto-HTTPS

### [x] Create OpenTofu Configuration

- [x] Create `terraform/main.tf`:
  - Proxmox provider config
  - 3 VM resources (media-services, infrastructure, custom-workloads)
  - Simple networking (single vmbr0 bridge, no VLANs)
  - GPU passthrough for media-services VM (AMD 780M at 0000:01:00.0)
- [x] Create `terraform/storage.tf`:
  - NFS share documentation
  - Ansible playbook reference for configuration
- [SKIP] Create `terraform/network.tf`:
  - Removed - using simple networking instead
  - No VLAN configuration
  - Firewall configured manually via Proxmox UI if needed
- [x] Initialize: `cd terraform && tofu init`

### [x] Create Ansible Configuration

**Ansible manages all Proxmox host configuration (repos, GPU passthrough, ZFS, NFS)**

- [x] Create `ansible/inventory.yml`:
  - Proxmox host + VMs
- [x] Create `ansible/playbooks/configure-proxmox.yml`:
  - Disable enterprise repos, add no-subscription repo
  - Configure GRUB for GPU passthrough
  - Create vfio-pci configuration
  - Import ZFS pools if needed
  - Install and configure NFS server
  - Configure NFS shares via ZFS
- [x] Create `ansible/playbooks/reboot-proxmox.yml`:
  - Reboot with verification
  - Check IOMMU and GPU driver binding
- [x] Create `ansible/playbooks/configure-vlans-gradual.yml`:
  - Gradual VLAN setup with step-by-step execution
  - Automatic connectivity testing and rollback support
  - Tags: backup, check, vlan-bridge, verify, rollback
- [x] Create `ansible/playbooks/create-ubuntu-cloud-template.yml`:
  - Automated Ubuntu cloud template creation
  - Cloud-init configuration with SSH keys
  - Template ID 9001, ready for VM deployment
- [ ] Create `ansible/playbooks/deploy-containers.yml`:
  - Install Docker Engine
  - Install Docker Compose plugin
  - Install GPU drivers (if eGPU configured):
    - NVIDIA: nvidia-driver-535, nvidia-container-toolkit
    - AMD: rocm-dkms (if needed)
  - Deploy all compose files from `../docker-compose/`
- [ ] Create example `ansible/docker-compose/app1.yml`
- [ ] Create `ansible/docker-compose/gpu-test.yml` (if eGPU configured):
  ```yaml
  services:
    gpu-test:
      image: nvidia/cuda:12.0-base
      command: nvidia-smi
      deploy:
        resources:
          reservations:
            devices:
              - driver: nvidia
                count: all
                capabilities: [gpu]
  ```

### [x] Create Renovate Configuration
- [ ] Create `renovate.json`:
  ```json
  {
    "extends": ["config:base"],
    "docker-compose": {
      "fileMatch": ["ansible/docker-compose/.*\\.yml$"]
    }
  }
  ```

### [x] Create CI/CD Workflows
- [ ] Create `.github/workflows/validate.yml`:
  - Run `nix flake check`
  - Run `tofu validate`
  - Run `ansible-playbook --syntax-check`
- [ ] Create `.github/workflows/deploy-nixos.yml`:
  - Trigger on merge to main
  - Run `tofu apply`
  - Run `nixos-rebuild switch` for both VMs
- [ ] Create `.github/workflows/deploy-custom.yml`:
  - Trigger on changes to `ansible/docker-compose/`
  - Run `ansible-playbook deploy-containers.yml`

## Deployment

**Architecture Decision:** Using Ubuntu VMs with Docker instead of NixOS for simpler deployment and management.

### [x] Deploy Infrastructure

- [x] Switched from telmate/proxmox to bpg/proxmox provider (better maintained)
- [x] Plan: `cd terraform && tofu plan -out=plan.tfplan`
- [x] Apply: `tofu apply plan.tfplan`
- [x] Fix: Added `machine = "q35"` for GPU passthrough support
- [x] Verify VMs created in Proxmox

**Created VMs:**

- media-services (100): 6 cores, 20GB RAM, AMD 780M GPU, VLANs 20+40
- infrastructure (101): 2 cores, 4GB RAM, VLANs 10+30
- custom-workloads (102): 4 cores, 28GB RAM, VLAN 20

### [x] Configure VLAN Routing

**Ubiquiti Dream Router 7 Configuration:**

- [x] Created VLAN 10 (Management): 192.168.10.0/24
- [x] Created VLAN 20 (Services): 192.168.20.0/24
- [x] Created VLAN 30 (Public): 192.168.30.0/24
- [x] Created VLAN 40 (Downloads): 192.168.40.0/24
- [x] Configured DHCP on all VLANs
- [x] Set Proxmox port to trunk mode ("All" profile)

**VM IP Assignments:**

- infrastructure: 192.168.10.222 (VLAN 10)
- media-services: 192.168.20.247 (VLAN 20)
- custom-workloads: 192.168.20.106 (VLAN 20)

**Note:** 2nd NICs on infrastructure (VLAN 30) and media-services (VLAN 40) need manual configuration - cloud-init only configures primary interface.

### [x] Verify Connectivity

- [x] All VMs reachable via SSH
- [x] Ansible connectivity verified
- [x] Updated ansible/inventory.yml with correct IPs

### [ ] Deploy Docker + Services

- [ ] Create Docker Compose files for media stack
- [ ] Deploy to media-services:

  ```bash
  ansible-playbook -i ansible/inventory.yml playbooks/deploy-containers.yml --limit media-services
  ```

- [ ] Verify: `ssh root@media-services docker ps`

**Services to deploy:**

- Jellyfin (with GPU transcoding)
- Sonarr, Radarr, Prowlarr
- qBittorrent
- Caddy (on infrastructure VM)

## Next Steps

### Immediate Priority

1. **Configure 2nd NICs** (optional but recommended for proper segmentation):

   - infrastructure: Enable ens19 for VLAN 30 (Public - Caddy external access)
   - media-services: Enable enp6s19 for VLAN 40 (Downloads - qBittorrent)

2. **Create Docker Compose files:**

   - `ansible/docker-compose/media-stack.yml` (Jellyfin, *arr stack, qBittorrent)
   - `ansible/docker-compose/caddy.yml` (reverse proxy)

3. **Update/create Ansible playbooks:**

   - `ansible/playbooks/deploy-containers.yml` (install Docker, deploy compose files)
   - Configure GPU passthrough for Jellyfin container

4. **Deploy services:**

   - Run Ansible playbook to deploy containers
   - Configure services (Jellyfin, *arr stack, etc.)
   - Setup Caddy reverse proxy

5. **NFS setup for Mac:**

   - Configure NFS exports on Proxmox
   - Mount NFS shares on Mac
   - Test performance

### Nice to Have

- Configure secondary NICs via cloud-init or Ansible
- Setup monitoring (Grafana, Prometheus)
- Configure automated backups
- Setup Renovate for container updates

## Mac Storage Configuration

### [ ] Mount NAS Storage on Mac
- [ ] Verify 10GbE connection to NAS
- [ ] Mount NVMe-backed storage:
  ```bash
  mkdir -p ~/Volumes/NAS-Fast
  mount -t nfs -o resvport,rw nas-ip:/tank-vms/mac-workspace ~/Volumes/NAS-Fast
  ```
- [ ] Optional: Mount HDD-backed storage for archives:
  ```bash
  mkdir -p ~/Volumes/NAS-Archive
  mount -t nfs -o resvport,rw nas-ip:/tank-media/data ~/Volumes/NAS-Archive
  ```
- [ ] Add to `/etc/fstab` for auto-mount (optional):
  ```
  nas-ip:/tank-vms/mac-workspace /Users/you/Volumes/NAS-Fast nfs resvport,rw 0 0
  ```
- [ ] Test performance: `dd if=/dev/zero of=~/Volumes/NAS-Fast/test bs=1m count=1000`
  - Expected: 400-800 MB/s over 10GbE

### [ ] Configure NAS for Mac Access
- [ ] Verify NFS exports: `zfs get sharenfs tank-vms/mac-workspace`
- [ ] Ensure Proxmox firewall allows NFS (port 2049)
- [ ] Optional: Enable SMB if NFS has issues:
  ```bash
  apt install samba
  # Configure /etc/samba/smb.conf
  ```

## Service Configuration

### [ ] Configure Jellyfin
- [ ] Access web UI: http://media-services:8096
- [ ] Complete setup wizard
- [ ] Dashboard → Playback → Enable VA-API
- [ ] Add media libraries:
  - Movies: /data/media/movies
  - TV: /data/media/tv
  - Music: /data/media/music
- [ ] Network → Known Proxies: Add Caddy IP

### [ ] Configure Prowlarr
- [ ] Access web UI: http://media-services:9696
- [ ] Settings → Indexers → Add indexers
- [ ] Settings → Apps → Add Sonarr (get API key from sops)
- [ ] Settings → Apps → Add Radarr (get API key from sops)
- [ ] Test sync

### [ ] Configure Sonarr
- [ ] Access web UI: http://media-services:8989
- [ ] Settings → Download Clients → Add qBittorrent
- [ ] Settings → Media Management → Root folder: /data/media/tv
- [ ] Settings → Profiles → Configure quality profiles

### [ ] Configure Radarr
- [ ] Access web UI: http://media-services:7878
- [ ] Settings → Download Clients → Add qBittorrent
- [ ] Settings → Media Management → Root folder: /data/media/movies
- [ ] Settings → Profiles → Configure quality profiles

### [ ] Configure qBittorrent
- [ ] Access web UI: http://media-services:8080
- [ ] Settings → Downloads → Default Save Path: /data/downloads/complete
- [ ] Settings → Downloads → Temp Path: /data/downloads/incomplete

### [ ] Configure Caddy
- [ ] Update domain in `nixos/hosts/infrastructure/caddy.nix`
- [ ] Point DNS to Proxmox public IP
- [ ] Deploy: `nixos-rebuild switch --flake .#infrastructure`
- [ ] Verify Let's Encrypt cert: `curl -I https://jellyfin.yourdomain.com`

## Validation

### [ ] Test GPU Passthrough

**Test iGPU (media-services VM):**
- [ ] SSH to media-services: `ssh root@media-services`
- [ ] Verify GPU visible: `lspci | grep -i vga`
- [ ] Install radeontop: `nix-shell -p radeontop`
- [ ] Run: `radeontop`
- [ ] Play 4K video in Jellyfin
- [ ] Verify GPU usage in radeontop

**Test eGPU (custom-workloads VM, if configured):**
- [ ] SSH to custom-workloads: `ssh ubuntu@custom-workloads`
- [ ] Verify GPU visible: `lspci | grep -i vga`
- [ ] Install drivers (NVIDIA example):
  ```bash
  sudo apt update && sudo apt install nvidia-driver-535
  sudo reboot
  ```
- [ ] Verify driver: `nvidia-smi` (NVIDIA) or `radeontop` (AMD)
- [ ] Test Docker GPU access:
  ```bash
  docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
  ```
- [ ] Verify OCuLink stability: leave GPU under load, monitor `dmesg` for PCIe errors

### [ ] Test Arr Workflow
- [ ] Access Jellyseerr (if configured) or directly request in Sonarr
- [ ] Request TV show
- [ ] Verify Prowlarr search
- [ ] Verify Sonarr grabs release
- [ ] Verify qBittorrent downloads
- [ ] Verify file moves to /data/media/tv
- [ ] Verify Jellyfin detects new episode

### [ ] Test Hardlinks
- [ ] Wait for download to complete
- [ ] Check inodes:
  ```bash
  ssh root@media-services
  ls -li /data/downloads/complete/file.mkv
  ls -li /data/media/tv/Show/file.mkv
  ```
- [ ] Verify same inode number (hardlink success)

### [ ] Test External Access
- [ ] Access https://jellyfin.yourdomain.com from external network
- [ ] Test playback
- [ ] Verify HTTPS certificate valid

### [ ] Test Backups
- [ ] Verify ZFS snapshots: `zfs list -t snapshot`
- [ ] Test snapshot rollback on test dataset
- [ ] Configure sanoid/syncoid if not auto-configured

### [ ] Test Mac Storage Performance
- [ ] Mount NFS share from Mac
- [ ] Benchmark read speed: `dd if=~/Volumes/NAS-Fast/testfile of=/dev/null bs=1m`
  - Target: >400 MB/s over 10GbE
- [ ] Benchmark write speed: `dd if=/dev/zero of=~/Volumes/NAS-Fast/testfile bs=1m count=1000`
  - Target: >400 MB/s over 10GbE
- [ ] Test with real workload (e.g., copy large video files)
- [ ] Verify NVMe pool usage: `zpool iostat -v tank-vms 1`

### [ ] Test NVMe Special Device (if configured)
- [ ] Check metadata on NVMe: `zpool status -v tank-media`
- [ ] Test directory listing speed: `time ls -R /tank-media/data/media`
- [ ] Verify small files on special device: `zdb -bbbs tank-media`

## Monitoring Setup

### [ ] Configure Monitoring
- [ ] Deploy Dozzle for container logs
- [ ] Deploy Grafana + Prometheus (if desired)
- [ ] Configure ZFS monitoring alerts
- [ ] Test alert notifications

## Documentation

### [ ] Create Documentation
- [ ] Document drive serial numbers (NVMe + HDD)
- [ ] Document NVMe upgrade path (if started with 2×2TB)
- [ ] Document network layout (IP assignments, 10GbE config)
- [ ] Document domain/DNS configuration
- [ ] Document NFS exports for Mac storage
- [ ] Document ZFS pool layout:
  - tank-vms: NVMe mirror for VMs + Mac storage
  - tank-media: HDD RAIDZ for media + special device
- [ ] Document GPU configuration:
  - iGPU (AMD 780M): PCI address, IOMMU group, passed to media-services
  - eGPU (if configured): model, PCI address, IOMMU group, passed to custom-workloads
  - OCuLink connection details (if applicable)
  - vfio-pci binding configuration
- [ ] Document backup procedures
- [ ] Document recovery procedures
- [ ] Document eGPU hot-swap warnings (if applicable):
  - Never disconnect eGPU while VM running
  - Proper shutdown sequence

## Renovate Integration

### [ ] Enable Renovate
- [ ] Install Renovate GitHub App on repository
- [ ] Configure Renovate to run on schedule
- [ ] Test: Manually trigger Renovate run
- [ ] Verify PR created for outdated image
- [ ] Merge test PR
- [ ] Verify CI deploys updated container

## Ongoing Maintenance Checklist

### Weekly
- [ ] Check ZFS pool health: `zpool status`
- [ ] Check disk SMART status
- [ ] Review failed container restarts

### Monthly
- [ ] Review and merge Renovate PRs
- [ ] Check backup retention
- [ ] Review storage usage
- [ ] Update NixOS VMs: `nixos-rebuild switch`

### Quarterly
- [ ] Test disaster recovery procedures
- [ ] Review security updates
- [ ] Audit firewall rules
