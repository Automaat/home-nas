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
- [x] ~~Edit `/etc/default/grub` for GPU passthrough~~ - NOT NEEDED for LXC approach
- [x] ~~Create `/etc/modprobe.d/vfio.conf`~~ - NOT NEEDED for LXC approach
- [x] GPU uses amdgpu driver on host (not vfio-pci)
- [x] LXC containers access GPU via direct device sharing

**Note:** Initial VM approach with vfio-pci binding abandoned due to AMD Phoenix 780M PSP firmware incompatibility with Linux VMs. LXC approach uses host's amdgpu driver directly.

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
  mkdir -p terraform ansible/{playbooks,docker-compose,secrets} docs .github/workflows
  ```

### [x] Setup Secrets Management
- [x] Get Proxmox SSH host key: `ssh root@proxmox-ip cat /etc/ssh/ssh_host_ed25519_key.pub`
- [x] Generate age key: `nix-shell -p ssh-to-age --run 'echo "<pubkey>" | ssh-to-age'`
- [x] Create `ansible/secrets/.sops.yaml`:
  ```yaml
  keys:
    - &admin age1xxx...
  creation_rules:
    - path_regex: secrets/.*\.yaml$
      key_groups:
        - age:
            - *admin
  ```

- [x] Create `ansible/secrets/secrets.yaml` with:

  - jellyfin_api_key
  - sonarr_api_key
  - radarr_api_key
  - prowlarr_api_key
  - qbittorrent_password
  - cloudflare_tunnel_token
- [x] Encrypt: `sops ansible/secrets/secrets.yaml`

## Infrastructure as Code

### [x] Create Media Services Architecture

**Architecture Evolution:** Migrated from single VM to 3 LXC containers (2026-02-16)

**Previous:** media-services VM (100) with GPU passthrough via UEFI/OVMF
**Current:** 3 unprivileged LXC containers with direct GPU device sharing

**Reason for Change:** AMD Phoenix 780M iGPU PSP firmware incompatible with Linux VM passthrough. LXC provides direct GPU access from host without VM virtualization layer.

**LXC Containers:**

- [x] LXC 110 (jellyfin): GPU-enabled services
  - Static IP: 192.168.20.191 (VLAN 20)
  - Services: Jellyfin, Jellyseerr, Ollama, Navidrome
  - GPU: /dev/dri/card0 + /dev/dri/renderD128 (AMD 780M)
  - Storage: /tank-media/data bind mount (supports hardlinks)

- [x] LXC 111 (media-management): *arr stack
  - Static IP: 192.168.20.192 (VLAN 20)
  - Services: Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Bookshelf, Subgen
  - Storage: /tank-media/data bind mount (supports hardlinks)

- [x] LXC 112 (downloads): VPN + downloads
  - Static IP: 192.168.40.162 (VLAN 40)
  - Services: Gluetun (VPN), qBittorrent
  - Network: Isolated on VLAN 40 for security
  - Storage: /tank-media/data bind mount (supports hardlinks)

**Key Implementation Details:**

- Unprivileged containers: UID mapping (container 1000 = host 101000)
- GPU access: Direct device sharing via lxc.mount.entry + lxc.cgroup2.devices.allow
- Subordinate GID mapping: video (44) and render (993) groups mapped
- All containers use bind mounts (NOT VirtioFS/NFS) for hardlink support

### [x] Create Infrastructure LXC
- [ ] Create LXC 101 for infrastructure services
- [ ] Create `ansible/playbooks/setup-infrastructure-lxc.yml`:
  - Create unprivileged LXC container
  - Static IP: 192.168.10.222 (VLAN 10)
  - Install Docker
  - Deploy cloudflared container
- [ ] Create `ansible/docker-compose/infrastructure-stack.yml`:
  - cloudflared (Cloudflare Tunnel)
  - Tunnel routes (jellyfin.yourdomain.com → http://192.168.20.191:8096)
  - WebSocket support
  - HTTPS handled by Cloudflare (no local certs needed)

### [x] Create OpenTofu Configuration

- [x] Create `terraform/main.tf`:
  - Proxmox provider config (bpg/proxmox)
  - 1 VM resource (custom-workloads)
  - ~~infrastructure VM~~ (replaced by LXC 101)
  - ~~media-services VM~~ (decommissioned - replaced by LXC 110+111+112)
  - VLAN networking (VLANs 10, 20, 30, 40)
  - All LXC containers managed via Ansible (not Terraform)
- [x] Create `terraform/storage.tf`:
  - NFS share documentation
  - Ansible playbook reference for configuration
- [SKIP] Create `terraform/network.tf`:
  - Removed - using simple networking instead
  - No VLAN configuration
  - Firewall configured manually via Proxmox UI if needed
- [x] Initialize: `cd terraform && tofu init`

### [x] Create Ansible Configuration

**Ansible manages all Proxmox host configuration (repos, GPU passthrough, ZFS, NFS) + LXC deployment**

- [x] Create `ansible/inventory.yml`:
  - Proxmox host + VMs + LXC containers
  - ~~media-services VM~~ (removed)
  - ~~infrastructure VM~~ (replaced by LXC)
  - LXC containers: infrastructure_lxc, jellyfin_lxc, media_management_lxc, downloads_lxc
- [x] Create `ansible/playbooks/configure-proxmox.yml`:
  - Disable enterprise repos, add no-subscription repo
  - ~~Configure GRUB for GPU passthrough~~ (not needed for LXC)
  - ~~Create vfio-pci configuration~~ (not needed for LXC)
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
- [x] Create `ansible/playbooks/setup-media-services-lxc.yml`:
  - Create LXC 110 with GPU access
  - Configure subordinate GID ranges for GPU groups
  - Setup GPU device sharing (card0, renderD128)
  - Configure ID mapping for unprivileged container
  - Mount /tank-media/data via bind mount
- [x] Create `ansible/playbooks/create-media-lxc-infrastructure.yml`:
  - Create LXC 111 (media-management)
  - Create LXC 112 (downloads with TUN device)
  - Configure static IPs
  - Mount storage bind mounts
- [x] Create `ansible/playbooks/migrate-vm-to-lxc.yml`:
  - Stop old media-services VM
  - Create 3 LXC containers
  - Install Docker in each container
  - Deploy compose stacks
  - Preserve existing configurations
- [ ] Create `ansible/playbooks/setup-infrastructure-lxc.yml`:
  - Create LXC 101 for infrastructure services
  - Static IP: 192.168.10.222 (VLAN 10)
  - Install Docker
  - Deploy cloudflared container
- [x] Create `ansible/docker-compose/jellyfin-stack.yml`:
  - Jellyfin (with GPU /dev/dri)
  - Jellyseerr
  - Ollama (with GPU)
  - Navidrome
- [x] Create `ansible/docker-compose/media-management-stack.yml`:
  - Sonarr, Radarr, Lidarr
  - Prowlarr, Bazarr, Bookshelf
  - Subgen (CPU-only, AMD GPU unsupported)
- [x] Create `ansible/docker-compose/downloads-stack.yml`:
  - Gluetun (VPN with WireGuard)
  - qBittorrent (network_mode: service:gluetun)
- [ ] Create `ansible/docker-compose/infrastructure-stack.yml`:
  - cloudflared (Cloudflare Tunnel)
  - Routes external traffic to internal services
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
  - Run `tofu validate`
  - Run `ansible-playbook --syntax-check`
  - Run `yamllint` and `ansible-lint`
- [ ] Create `.github/workflows/deploy-infra.yml`:
  - Trigger on merge to main
  - Run `tofu apply`
  - Run Ansible playbooks for LXC deployment
- [ ] Create `.github/workflows/deploy-containers.yml`:
  - Trigger on changes to `ansible/docker-compose/`
  - Run `ansible-playbook deploy-containers.yml`

## Deployment

**Architecture Decision:** Using LXC containers for all services (better GPU compatibility, lighter weight).

### [x] Deploy Infrastructure

- [x] Switched from telmate/proxmox to bpg/proxmox provider (better maintained)
- [x] Plan: `cd terraform && tofu plan -out=plan.tfplan`
- [x] Apply: `tofu apply plan.tfplan`
- [x] Migrated media-services VM to 3 LXC containers (2026-02-16)
- [x] Decommissioned media-services VM (100)
- [ ] Replace infrastructure VM with LXC 101

**Active VMs:**

- custom-workloads (102): 4 cores, 28GB RAM, VLAN 20

**Active LXC Containers:**

- jellyfin (110): 192.168.20.191, VLAN 20, GPU-enabled
- media-management (111): 192.168.20.192, VLAN 20
- downloads (112): 192.168.40.162, VLAN 40

**Planned LXC:**

- infrastructure (101): 192.168.10.222, VLAN 10, cloudflared

**Decommissioned:**

- ~~media-services (100)~~: Replaced by LXC 110+111+112
- ~~infrastructure VM (101)~~: To be replaced by LXC 101

### [x] Configure VLAN Routing

**Ubiquiti Dream Router 7 Configuration:**

- [x] Created VLAN 10 (Management): 192.168.10.0/24
- [x] Created VLAN 20 (Services): 192.168.20.0/24
- [x] Created VLAN 30 (Public): 192.168.30.0/24
- [x] Created VLAN 40 (Downloads): 192.168.40.0/24
- [x] Configured DHCP on all VLANs
- [x] Set Proxmox port to trunk mode ("All" profile)

**VM IP Assignments:**

- custom-workloads: 192.168.20.106 (VLAN 20)

**LXC IP Assignments (Static):**

- infrastructure (101): 192.168.10.222 (VLAN 10) - planned
- jellyfin (110): 192.168.20.191 (VLAN 20)
- media-management (111): 192.168.20.192 (VLAN 20)
- downloads (112): 192.168.40.162 (VLAN 40)

**Note:** LXC containers use static IPs configured via `pct set`.

### [x] Verify Connectivity

- [x] All VMs reachable via SSH
- [x] Ansible connectivity verified
- [x] Updated ansible/inventory.yml with correct IPs

### [x] Migrate VM to LXC Containers

**Issue:** AMD Phoenix 780M iGPU GPU passthrough failed in Linux VMs (PSP firmware issue)

**Investigation:**
- VM GPU passthrough: AMD 780M visible but /dev/dri/renderD128 missing
- Tried: rombar=true, different VBIOS files, driver reinstalls
- Root cause: AMD Phoenix/780M PSP firmware incompatible with Linux VM passthrough
- Works in Windows VMs, consistently fails in Linux VMs (known issue)

**Solution:** Migrate from single VM to 3 LXC containers with direct GPU sharing

**Migration Process (2026-02-16):**

1. [x] Created 3 Docker Compose stack files:
   - jellyfin-stack.yml (GPU services)
   - media-management-stack.yml (*arr stack)
   - downloads-stack.yml (VPN + qBittorrent)

2. [x] Created Ansible playbooks:
   - setup-media-services-lxc.yml (LXC 110 with GPU)
   - create-media-lxc-infrastructure.yml (LXC 111 + 112)
   - migrate-vm-to-lxc.yml (automated migration)

3. [x] Executed migration:
   - Stopped media-services VM containers
   - Created 3 unprivileged LXC containers
   - Configured GPU device sharing for LXC 110
   - Deployed Docker stacks to each LXC
   - Fixed UID mapping issues (1000→101000)
   - Configured static IPs
   - Verified all services operational

4. [x] Decommissioned media-services VM (100):
   - Destroyed VM from Proxmox
   - Removed from Terraform config
   - Removed from Ansible inventory
   - Committed changes

**Issues Fixed:**

- Permission errors: chown -R 101000:101000 on all service configs
- GPU access: Subordinate GID mapping for video (44) and render (993)
- Network: Assigned static IPs to all LXC containers
- TUN device: Added /dev/net/tun for Gluetun VPN in LXC 112

**Result:** All services running on LXC with GPU transcoding ready to test

### [x] Deploy Docker + Services

- [x] Created 3 Docker Compose files (jellyfin, media-management, downloads)
- [x] Deployed to LXC containers:

  ```bash
  ansible-playbook -i ansible/inventory.yml playbooks/migrate-vm-to-lxc.yml
  ```

- [x] Fixed permission issues (UID mapping 1000→101000)
- [x] Configured static IPs for all LXC containers
- [x] Verified: All containers running and accessible

**Services deployed (LXC 110 - Jellyfin Stack):**

- Jellyfin (GPU: /dev/dri/card0 + renderD128) - http://192.168.20.191:8096
- Jellyseerr - http://192.168.20.191:5055
- Ollama (GPU) - http://192.168.20.191:11434
- Navidrome - http://192.168.20.191:4533

**Services deployed (LXC 111 - Media Management):**

- Sonarr - http://192.168.20.192:8989
- Radarr - http://192.168.20.192:7878
- Lidarr - http://192.168.20.192:8686
- Prowlarr - http://192.168.20.192:9696
- Bazarr - http://192.168.20.192:6767
- Bookshelf - http://192.168.20.192:8787
- Subgen (CPU) - http://192.168.20.192:9000

**Services deployed (LXC 112 - Downloads):**

- qBittorrent (via Gluetun VPN) - http://192.168.40.162:8080
- Gluetun (WireGuard VPN) - healthy

**Status (2026-02-16):**

- [x] All services deployed and running
- [x] Basic configuration complete (media libraries, indexers, download clients)
- [x] Workflow validated (Prowlarr → Sonarr/Radarr → qBittorrent → Jellyfin)
- [x] Hardlinks working correctly
- [ ] GPU transcoding not yet tested
- [ ] Cloudflare Tunnel pending
- [ ] Mac NFS storage pending

## Next Steps

### Immediate Priority

1. **GPU Transcoding Validation:**

   - Test 4K video transcoding in Jellyfin UI
   - Monitor GPU usage: `cat /sys/class/drm/card0/device/gpu_busy_percent`
   - Verify VA-API working with AMD 780M iGPU

2. **Mac Storage Setup:**

   - Configure NFS export: `zfs set sharenfs="rw=@192.168.0.0/24,no_root_squash" tank-vms/mac-workspace`
   - Mount NFS share on Mac over 10GbE
   - Benchmark performance (target: 400-800 MB/s)

3. **Cloudflare Tunnel Setup:**

   - Create infrastructure LXC 101 (192.168.10.222, VLAN 10)
   - Deploy cloudflared via Docker Compose
   - Create tunnel in Cloudflare dashboard
   - Configure routes (jellyfin.yourdomain.com → http://192.168.20.191:8096)
   - Test external HTTPS access (no port forwarding needed)

### Nice to Have

- Setup monitoring (Dozzle for logs, Grafana/Prometheus)
- Configure automated ZFS snapshots (sanoid/syncoid)
- Setup Renovate for container updates
- Document network layout, GPU config, backup procedures

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

### [x] Configure Jellyfin
- [x] Access web UI: http://192.168.20.191:8096
- [x] Complete setup wizard
- [x] Dashboard → Playback → Enable VA-API
- [x] Add media libraries:
  - Movies: /data/media/movies
  - TV: /data/media/tv
  - Music: /data/media/music
- [ ] Network → Known Proxies: Add Cloudflare IPs (pending tunnel deployment)

### [x] Configure Prowlarr
- [x] Access web UI: http://192.168.20.192:9696
- [x] Settings → Indexers → Add indexers
- [x] Settings → Apps → Add Sonarr
- [x] Settings → Apps → Add Radarr
- [x] Test sync

### [x] Configure Sonarr
- [x] Access web UI: http://192.168.20.192:8989
- [x] Settings → Download Clients → Add qBittorrent
- [x] Settings → Media Management → Root folder: /data/media/tv
- [x] Settings → Profiles → Configure quality profiles

### [x] Configure Radarr
- [x] Access web UI: http://192.168.20.192:7878
- [x] Settings → Download Clients → Add qBittorrent
- [x] Settings → Media Management → Root folder: /data/media/movies
- [x] Settings → Profiles → Configure quality profiles

### [x] Configure qBittorrent
- [x] Access web UI: http://192.168.40.162:8080
- [x] Settings → Downloads → Default Save Path: /data/downloads/complete
- [x] Settings → Downloads → Temp Path: /data/downloads/incomplete

### [ ] Configure Cloudflare Tunnel
- [ ] Create infrastructure LXC 101:
  ```bash
  ansible-playbook -i ansible/inventory.yml playbooks/setup-infrastructure-lxc.yml
  ```
- [ ] Authenticate cloudflared (one-time): `cloudflared tunnel login`
- [ ] Create tunnel: `cloudflared tunnel create home-nas`
- [ ] Save tunnel credentials to `ansible/secrets/secrets.yaml` (sops-encrypted)
- [ ] Create `ansible/docker-compose/infrastructure-stack.yml`:
  ```yaml
  services:
    cloudflared:
      image: cloudflare/cloudflared:latest
      command: tunnel run
      environment:
        TUNNEL_TOKEN: ${CLOUDFLARE_TUNNEL_TOKEN}
      restart: unless-stopped
  ```
- [ ] Or use config file approach with ingress rules
- [ ] Add DNS record in Cloudflare dashboard (CNAME to tunnel)
- [ ] Deploy: `ansible-playbook -i ansible/inventory.yml playbooks/deploy-infrastructure.yml`
- [ ] Test access: `curl -I https://jellyfin.yourdomain.com`

## Validation

### [x] Test GPU Access (LXC Direct Sharing)

**Architecture:** Direct GPU device sharing from Proxmox host to LXC (no VM passthrough)

**Host GPU Configuration:**

- [x] AMD 780M iGPU using amdgpu driver on host
- [x] GPU devices: /dev/dri/card0 (video:44), /dev/dri/renderD128 (render:993)
- [x] Subordinate GID mapping configured (/etc/subgid)
- [x] VA-API verified with Mesa Gallium driver

**LXC 110 GPU Access:**

- [x] LXC config: lxc.mount.entry for card0 + renderD128
- [x] LXC config: lxc.cgroup2.devices.allow for GPU majors
- [x] ID mapping: video (44) and render (993) groups mapped
- [x] Jellyfin container has GPU access (/dev/dri mounted)
- [x] VA-API codecs: H264, HEVC, VP9, AV1
- [ ] Test 4K video transcoding in Jellyfin UI
- [ ] Monitor GPU usage: `cat /sys/class/drm/card0/device/gpu_busy_percent`

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

### [x] Test Arr Workflow
- [x] Access Jellyseerr (if configured) or directly request in Sonarr
- [x] Request TV show
- [x] Verify Prowlarr search
- [x] Verify Sonarr grabs release
- [x] Verify qBittorrent downloads
- [x] Verify file moves to /data/media/tv
- [x] Verify Jellyfin detects new episode

### [x] Test Hardlinks
- [x] Wait for download to complete
- [x] Check inodes: verified same inode between downloads and media
- [x] Verify same inode number (hardlink success)

### [ ] Test External Access
- [ ] Access https://jellyfin.yourdomain.com from external network
- [ ] Test playback
- [ ] Verify HTTPS certificate (Cloudflare-managed)

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
- [ ] Update LXC containers: `pct update` or rebuild from Ansible

### Quarterly
- [ ] Test disaster recovery procedures
- [ ] Review security updates
- [ ] Audit firewall rules
