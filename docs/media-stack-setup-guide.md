# Media Stack Setup Guide

Complete guide for deploying Jellyfin + *arr stack on Proxmox Ubuntu VM with GPU transcoding.

## Architecture

**Stack Components:**

- **Jellyfin**: Media server (GPU transcoding via AMD 780M)
- **Sonarr**: TV show automation
- **Radarr**: Movie automation
- **Prowlarr**: Indexer management
- **Bazarr**: Subtitle automation
- **qBittorrent**: Download client (routed via VPN)
- **Gluetun**: WireGuard VPN container
- **Jellyseerr**: Media request management

**Infrastructure:**

- **VM**: media-services (Ubuntu 24.04, 6 cores, 20GB RAM)
- **GPU**: AMD 780M iGPU (PCI passthrough)
- **Storage**: /data (ZFS tank-media RAIDZ1)
- **Network**: VLAN 20 (Services), VLAN 40 (Downloads)

## Prerequisites

### 1. Proxmox VM (via Terraform)

VM must exist with:

- Ubuntu cloud template (ID 9001)
- AMD 780M GPU passed through (PCI 0000:01:00.0)
- BIOS: OVMF (UEFI) with vbios ROM
- 2 NICs (VLAN 20 + VLAN 40)

**Verify VM exists:**

```bash
ssh root@192.168.0.101  # Proxmox host
qm list | grep media-services
```

### 2. VPN Configuration

**ProtonVPN WireGuard config required.**

**Get config:**

1. Login to ProtonVPN account
2. Downloads → WireGuard configuration
3. Download .conf file
4. Extract PrivateKey value

**Store in secrets:**

```bash
sops ansible/secrets/secrets.yaml
# Add entire .conf content to protonvpn_wg_conf key
```

### 3. ZFS Storage

**Required datasets on tank-media:**

```bash
# SSH to Proxmox host
zfs list tank-media/data
zfs list tank-media/data/media
zfs list tank-media/data/downloads
```

**Create if missing:**

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

**Mount to VM:**

- Via Proxmox bind mount (recommended)
- Or NFS share from Proxmox

## Deployment

### Step 1: Install GPU Drivers

**Run:**

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/setup-media-services-gpu.yml
```

**What it does:**

- Installs linux-modules-extra (amdgpu kernel module)
- Installs Mesa VA-API drivers (hardware transcoding)
- Loads amdgpu module
- Configures autoload on boot
- Verifies /dev/dri/card0 exists

**Verify:**

```bash
ssh root@192.168.20.191  # media-services VM
ls -la /dev/dri/
# Should show: card0, renderD128
lspci | grep VGA
# Should show: AMD Phoenix3
```

### Step 2: Deploy Media Stack

**Run:**

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy-media-stack.yml
```

**What it does:**

1. Installs Docker Engine + Docker Compose v2
2. Creates directory structure (/data/*)
3. Extracts WireGuard private key from sops
4. Creates .env file with WIREGUARD_PRIVATE_KEY
5. Deploys docker-compose.yml to /opt/media-stack/
6. Pulls images and starts containers
7. Verifies all containers running

**Verify:**

```bash
ssh root@192.168.20.191
docker ps
# Should show 8 containers: gluetun, qbittorrent, jellyfin, sonarr, radarr, prowlarr, bazarr, jellyseerr
```

### Step 3: Test VPN Connection

**Check Gluetun:**

```bash
ssh root@192.168.20.191
docker logs gluetun | grep "ip"
# Should show ProtonVPN IP, NOT your home IP
```

**Check qBittorrent:**

```bash
curl http://192.168.20.191:8080
# Should return qBittorrent WebUI (default: admin/adminadmin)
```

**Verify VPN isolation:**

```bash
docker exec qbittorrent curl ifconfig.me
# Should show ProtonVPN IP
```

### Step 4: Test GPU Transcoding

**Access Jellyfin:**

```bash
open http://192.168.20.191:8096
```

**Enable VA-API:**

1. Dashboard → Playback
2. Hardware acceleration: Video Acceleration API (VA-API)
3. VA-API Device: /dev/dri/renderD128
4. Enable hardware decoding for: H264, HEVC, VP9
5. Save

**Test transcode:**

1. Upload test video to /data/media/movies/
2. Play in browser (force transcode by selecting lower quality)
3. Monitor GPU usage:

```bash
ssh root@192.168.20.191
watch -n1 'cat /sys/class/drm/card0/device/gpu_busy_percent'
# Should show >0% during transcode
```

## Service Configuration

### Prowlarr (Indexer Manager)

**Access:** http://192.168.20.191:9696

**Setup:**

1. Settings → Indexers → Add indexers (1337x, RARBG, etc.)
2. Settings → Apps → Add Sonarr
   - Name: Sonarr
   - Prowlarr Server: http://prowlarr:9696
   - Sonarr Server: http://sonarr:8989
   - API Key: (get from Sonarr → Settings → General)
3. Settings → Apps → Add Radarr
   - Name: Radarr
   - Prowlarr Server: http://prowlarr:9696
   - Radarr Server: http://radarr:7878
   - API Key: (get from Radarr → Settings → General)
4. Test sync (Prowlarr → Apps → Sync)

### Sonarr (TV Shows)

**Access:** http://192.168.20.191:8989

**Setup:**

1. Settings → Media Management
   - Root folder: /data/media/tv
   - File Naming: Standard Episode Format (customize if needed)
   - Enable: Create empty series folders
2. Settings → Download Clients → Add → qBittorrent
   - Host: gluetun (shares network with qBittorrent)
   - Port: 8080
   - Username: admin
   - Password: adminadmin (change in qBittorrent first)
   - Category: sonarr
   - Test + Save
3. Settings → Profiles
   - Quality Profiles: 1080p or 2160p (depending on preference)

### Radarr (Movies)

**Access:** http://192.168.20.191:7878

**Setup:**

1. Settings → Media Management
   - Root folder: /data/media/movies
   - File Naming: Standard Movie Format
   - Enable: Create empty movie folders
2. Settings → Download Clients → Add → qBittorrent
   - Host: gluetun
   - Port: 8080
   - Username: admin
   - Password: adminadmin
   - Category: radarr
   - Test + Save
3. Settings → Profiles
   - Quality Profiles: 1080p or 2160p

### qBittorrent

**Access:** http://192.168.20.191:8080

**Setup:**

1. Login: admin/adminadmin
2. Tools → Options → Downloads
   - Default Save Path: /data/downloads/complete
   - Temp Path: /data/downloads/incomplete
   - Use Automatic Torrent Management: Enabled
3. Tools → Options → WebUI
   - Change password (update in Sonarr/Radarr after)
4. Tools → Options → Advanced
   - Network Interface: tun0 (VPN interface)
   - Optional: Enable anonymous mode

### Bazarr (Subtitles)

**Access:** http://192.168.20.191:6767

**Setup:**

1. Languages → Add language (e.g., English)
2. Providers → Add providers (OpenSubtitles, Subscene, etc.)
3. Sonarr → Enable + configure:
   - Address: http://sonarr:8989
   - API Key: (from Sonarr)
4. Radarr → Enable + configure:
   - Address: http://radarr:7878
   - API Key: (from Radarr)

### Jellyseerr (Request Management)

**Access:** http://192.168.20.191:5055

**Setup:**

1. Use Jellyfin Account → Sign in
2. Connect Jellyfin:
   - Server: http://jellyfin:8096
   - Sign in with Jellyfin admin account
3. Configure Sonarr:
   - Server: http://sonarr:8989
   - API Key: (from Sonarr)
   - Quality Profile: 1080p
   - Root Folder: /data/media/tv
4. Configure Radarr:
   - Server: http://radarr:7878
   - API Key: (from Radarr)
   - Quality Profile: 1080p
   - Root Folder: /data/media/movies

### Jellyfin

**Access:** http://192.168.20.191:8096

**Setup:**

1. Complete setup wizard (create admin account)
2. Dashboard → Playback → Enable VA-API (see Step 4 above)
3. Add media libraries:
   - Movies: /data/media/movies
   - TV Shows: /data/media/tv
   - Music: /data/media/music
4. Settings → Networking → Known Proxies:
   - Add Caddy/reverse proxy IP when configured

## Verification

### Test Workflow End-to-End

1. **Request media** (Jellyseerr):
   - Request TV show or movie
   - Verify request appears in Sonarr/Radarr

2. **Search indexers** (Prowlarr):
   - Verify Prowlarr searches configured indexers
   - Check Prowlarr → History

3. **Download** (qBittorrent):
   - Verify torrent added to qBittorrent
   - Check download progress
   - Verify using VPN IP: `docker exec qbittorrent curl ifconfig.me`

4. **Import** (Sonarr/Radarr):
   - Verify file moved to /data/media/tv or /data/media/movies
   - Check hardlink created (same inode):

```bash
ssh root@192.168.20.191
ls -li /data/downloads/complete/file.mkv
ls -li /data/media/tv/Show/file.mkv
# Verify same inode number
```

5. **Detect** (Jellyfin):
   - Verify media appears in Jellyfin library
   - Test playback
   - Force transcode (select lower quality)
   - Verify GPU usage >0%

### Check Hardlinks

**Critical for disk space efficiency.**

**Verify:**

```bash
ssh root@192.168.20.191
ls -li /data/downloads/complete/Movie.mkv
ls -li /data/media/movies/Movie/Movie.mkv
```

**Expected:** Same inode number = hardlink (file stored once)

**If different inodes:**

- Check both paths share same mountpoint: `df -h /data/downloads /data/media`
- Verify Docker volumes use /data (not separate mounts)
- Ensure Sonarr/Radarr use /data root (not /data/media)

## Troubleshooting

### GPU Not Working

**Symptom:** Jellyfin transcoding uses CPU (100% CPU usage)

**Fix:**

```bash
# SSH to media-services
ssh root@192.168.20.191

# Verify GPU device
ls -la /dev/dri/
# Should show: card0, renderD128

# Check driver
lspci -nnk -d 1002:
# Should show: Kernel driver in use: amdgpu

# Reload GPU playbook
exit
cd ansible
ansible-playbook -i inventory.yml playbooks/setup-media-services-gpu.yml
```

### VPN Not Working

**Symptom:** qBittorrent shows home IP, not VPN IP

**Fix:**

```bash
# Check Gluetun logs
ssh root@192.168.20.191
docker logs gluetun | tail -50

# Common issues:
# - Wrong PrivateKey in .env
# - ProtonVPN server down (change VPN_ENDPOINT_IP)
# - Firewall blocking port 51820

# Test VPN manually
docker exec gluetun curl ifconfig.me
# Should show ProtonVPN IP

# Restart Gluetun
docker restart gluetun
docker restart qbittorrent  # Depends on Gluetun
```

### Container Won't Start

**Check logs:**

```bash
ssh root@192.168.20.191
docker ps -a  # See stopped containers
docker logs <container-name>
```

**Common fixes:**

- Missing /data directories → Rerun deploy playbook
- Port conflict → Check `netstat -tulpn | grep <port>`
- Permission issues → `chown -R 1000:1000 /data/<service>`

### Hardlinks Not Working

**Check mountpoints:**

```bash
ssh root@192.168.20.191
df -h /data/downloads /data/media
# Must show same filesystem (tank-media/data)
```

**If different filesystems:**

- Check Proxmox MP (MountPoint) configuration
- Both paths must map to same ZFS dataset
- Recreate VM mountpoints if needed

### Prowlarr Not Syncing

**Verify connectivity:**

```bash
ssh root@192.168.20.191
docker exec prowlarr curl http://sonarr:8989/api/v3/system/status -H "X-Api-Key: <API_KEY>"
# Should return JSON
```

**Common issues:**

- Wrong API key → Copy from Sonarr/Radarr → Settings → General
- Network isolation → All containers on default bridge (should work)
- Service not running → `docker ps | grep sonarr`

## Maintenance

### Update Containers

**Renovate auto-creates PRs for updates.**

**Manual update:**

```bash
cd ansible
# Edit docker-compose/media-stack.yml (update image tags)
ansible-playbook -i inventory.yml playbooks/deploy-media-stack.yml
```

### Backup Configuration

**Container configs stored in /data/*/config.**

**Backup:**

```bash
# SSH to Proxmox host
zfs snapshot tank-media/data@$(date +%Y%m%d-%H%M%S)
zfs list -t snapshot | grep tank-media/data
```

**Restore:**

```bash
# SSH to Proxmox host
zfs rollback tank-media/data@<snapshot-name>
```

### Monitor Disk Usage

**Check ZFS pool:**

```bash
# SSH to Proxmox host
zpool status tank-media
zfs list tank-media/data
```

**Check downloads:**

```bash
ssh root@192.168.20.191
du -sh /data/downloads/*
du -sh /data/media/*
```

## Security Notes

### VPN Kill Switch

Gluetun configured with firewall rules:

- Blocks all traffic except VPN tunnel
- qBittorrent network_mode: service:gluetun (cannot bypass)

**Verify:**

```bash
# Stop Gluetun
docker stop gluetun
# qBittorrent should have no connectivity (expected)
docker start gluetun
```

### API Keys

**Never commit unencrypted API keys.**

**Rotation:**

1. Generate new key in service UI
2. Update Prowlarr/Jellyseerr connections
3. Update sops secrets if automated

### Exposed Ports

**Current exposure:**

- 8096 (Jellyfin): LAN only (VLAN 20)
- 8080 (qBittorrent): LAN only (VLAN 20)
- 8989, 7878, 9696, 6767, 5055: LAN only

**External access:** Use Caddy reverse proxy (infrastructure VM)

## Next Steps

1. **Configure Caddy** (infrastructure VM):
   - Reverse proxy for Jellyfin
   - SSL via Let's Encrypt
   - Access via https://jellyfin.yourdomain.com

2. **Add monitoring:**
   - Dozzle (container logs)
   - Grafana + Prometheus (metrics)

3. **Setup notifications:**
   - Sonarr/Radarr → Discord/Telegram webhooks
   - Jellyseerr → Email notifications

4. **Configure backups:**
   - Automated ZFS snapshots (sanoid)
   - Offsite backup (syncoid)
