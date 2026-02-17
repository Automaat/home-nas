# VPN vs Direct Download Speed Analysis

## Executive Summary

**Conclusion for Poland:** VPN not needed for torrenting - no ISP throttling detected, 3.6x faster without VPN.

## Speed Test Results

| Configuration | Speed | Line Utilization | Notes |
|--------------|-------|------------------|-------|
| WITH VPN (PIA Netherlands) | 15 MB/s | 20% | VPN overhead limiting speed |
| WITHOUT VPN (Direct) | 31-55 MB/s | 73% | Near-optimal for torrent traffic |

**Test setup:**
- ISP: 600 Mbps (75 MB/s theoretical max)
- Torrent: Ubuntu 24.04.1 Desktop ISO (well-seeded, 36+ peers)
- Location: Poland
- Date: 2026-02-16

## Issues Found & Fixed

### 1. Bandwidth Limits (10 MB/s cap)

**Problem:** Alternative rate limits capping speeds at exactly 10 MB/s
```
Alt download limit: 10240 KB/s = 10 MB/s
Alt upload limit: 10240 KB/s = 10 MB/s
```

**Fix:** Removed all bandwidth limits via API
```bash
docker exec qbittorrent curl -s -X POST 'http://127.0.0.1:8080/api/v2/app/setPreferences' \
  --data-urlencode 'json={"alt_dl_limit":0,"alt_up_limit":0,"dl_limit":0,"up_limit":0}'
```

**Impact:** Initial speeds improved from 0.03 MB/s to 2-3 MB/s

### 2. Permissions Issue

**Problem:** `/data/downloads` owned by root, qBittorrent runs as UID 1000
```bash
drwxr-xr-x  2 root root 4096 /data/downloads
```

**Symptoms:** All torrents entering "error" state immediately

**Fix:**
```bash
chown -R 1000:1000 /data/downloads
```

**Impact:** Torrents started downloading successfully (2.83 MB/s initially)

### 3. Port Mismatch

**Problem:**
- PIA assigned port: 47528
- qBittorrent configured: 47528 ✓
- Gluetun exposing: 51413 ✗

**Result:** No incoming connections through VPN

**Fix:** Updated docker-compose.yml
```yaml
gluetun:
  ports:
    - 8080:8080
    - 47528:47528      # Changed from 51413
    - 47528:47528/udp  # Changed from 51413
```

**Impact:** Incoming connections established, speeds improved to 15 MB/s with VPN

### 4. VPN Overhead

**Problem:** PIA VPN reducing throughput by ~50%

**Analysis:**
- VPN adds encryption/routing overhead
- Netherlands server may be congested
- Additional latency per packet

**Solution:** Disabled VPN for Poland (no ISP throttling detected)

**Impact:** Speeds jumped from 15 MB/s to 55 MB/s (3.6x improvement)

## Configuration Details

### qBittorrent Optimizations Applied

**Connection settings:**
```
Listen port: 47528 (PIA forwarded port when using VPN)
Max connections: 500 global / 100 per torrent
Upload slots: 20 global / 4 per torrent
UPnP: Disabled (not needed with proper port forwarding)
```

**Protocol settings:**
```
DHT: Enabled
PEX: Enabled
LSD: Enabled
Encryption: Prefer encryption (mode 1)
```

**Performance settings:**
```
Disk cache: 1024 MiB
File pool size: 5000
Async IO threads: 8
```

**Bandwidth limits:**
```
All set to 0 (unlimited)
```

### Docker Compose Configurations

#### With VPN (15 MB/s)

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:v3.41.1
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - 8080:8080
      - 47528:47528      # Must match PIA forwarded port
      - 47528:47528/udp
    environment:
      - VPN_SERVICE_PROVIDER=private internet access
      - SERVER_REGIONS=Netherlands
      - VPN_PORT_FORWARDING=on
    volumes:
      - /data/gluetun:/gluetun
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:20.04.1
    container_name: qbittorrent
    network_mode: container:gluetun  # Route through VPN
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /data/qbittorrent/config:/config
      - /data/downloads:/data/downloads
    depends_on:
      gluetun:
        condition: service_healthy
    restart: unless-stopped
```

**Access:** http://192.168.20.106:8080 (via gluetun)

#### Without VPN (55 MB/s) - Recommended for Poland

```yaml
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:20.04.1
    container_name: qbittorrent
    network_mode: host  # Direct network access
    environment:
      - PUID=1000
      - PGID=1000
      - WEBUI_PORT=8080
    volumes:
      - /data/qbittorrent/config:/config
      - /data/downloads:/data/downloads
    restart: unless-stopped
```

**Note:** gluetun can be removed entirely or commented out

**Access:** http://192.168.20.106:8080 (direct)

## Poland-Specific Findings

### ISP Throttling Test

**Method:** Compare speeds with and without VPN on same torrent

**Results:**
- WITHOUT VPN: 55 MB/s
- WITH VPN: 15 MB/s

**Conclusion:** No ISP throttling detected. If ISP were throttling, VPN would show higher speeds.

### Legal Considerations

**Copyright law in Poland:**
- Downloading for personal use: Gray area
- Uploading/sharing (torrenting): Technically illegal but rarely enforced
- No known prosecutions for personal torrenting
- ISPs don't monitor or forward copyright notices
- No "three strikes" laws

**Risk assessment:** Very low legal risk for personal use in Poland

**Reference:** See research from 2026-02-16 session

## Recommendations

### For Poland

1. **Don't use VPN for torrenting** - no benefit, 50% speed penalty
2. **Enable UPnP** on router for automatic port forwarding
3. **Use host network mode** for maximum performance
4. **Monitor speeds** - should achieve 40-60 MB/s on well-seeded torrents

### For Countries with ISP Throttling

If you need VPN (US, UK, Germany, etc.):

1. **Use PIA port forwarding:**
   - Check assigned port: `docker logs gluetun | grep "port forwarded"`
   - Update qBittorrent to use that port
   - Update Gluetun ports mapping to match

2. **Try different VPN servers:**
   - Some regions have better throughput
   - Test Netherlands, Switzerland, Sweden

3. **Monitor port forwarding:**
   - PIA changes ports every 60 days
   - Consider automation: [gluetun-qbittorrent-port-manager](https://github.com/SnoringDragon/gluetun-qbittorrent-port-manager)

## Switching Between Modes

### Enable VPN

```bash
cd ~/sideprojects/home-nas
# Restore VPN config (see "With VPN" section above)
nano ansible/docker-compose/downloads-stack.yml
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
```

### Disable VPN

```bash
cd ~/sideprojects/home-nas
# Use host network config (see "Without VPN" section above)
nano ansible/docker-compose/downloads-stack.yml
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
```

## Performance Metrics

### Expected Speeds by Configuration

| Setup | Expected Speed | % of 600 Mbps Line |
|-------|---------------|---------------------|
| Optimal (no VPN, well-seeded) | 40-60 MB/s | 53-80% |
| With VPN (PIA) | 10-20 MB/s | 13-27% |
| With bandwidth limits | Capped at limit | Variable |
| With permission errors | 0 MB/s | 0% (errors) |

### Bottleneck Identification

1. **< 1 MB/s:** Check permissions, bandwidth limits, port forwarding
2. **10 MB/s exactly:** Check for bandwidth caps (alt_dl_limit)
3. **15-20 MB/s with VPN:** Normal VPN overhead
4. **40-60 MB/s:** Optimal for torrent traffic
5. **> 60 MB/s:** Rare, requires exceptional swarm

## Troubleshooting

### Speeds still slow after fixes?

**Check torrent health:**
```bash
# Via API
docker exec qbittorrent curl -s 'http://127.0.0.1:8080/api/v2/torrents/info' | jq '.[0] | {name, num_seeds, num_leechs, dlspeed}'
```

**Need >10 seeds for good speeds. If seeds < 5, try different torrent.**

### Port forwarding not working?

**Test with VPN:**
```bash
# Check PIA assigned port
docker logs gluetun | grep "port forwarded"

# Verify qBittorrent using same port
docker exec qbittorrent curl -s 'http://127.0.0.1:8080/api/v2/app/preferences' | jq '.listen_port'
```

**Ports must match!**

### Torrents entering error state?

**Check permissions:**
```bash
ls -la /data/downloads
# Should show: drwxr-xr-x ubuntu ubuntu

# Fix if needed:
chown -R 1000:1000 /data/downloads
```

## Related Documentation

- [VPN Testing Procedures](vpn-testing.md) - How to safely test with/without VPN
- [qBittorrent Configuration](https://github.com/qbittorrent/qBittorrent/wiki/Explanation-of-Options-in-qBittorrent)

## Change Log

- **2026-02-16:** Initial testing and documentation
  - Identified and fixed bandwidth limits (10 MB/s cap)
  - Fixed permissions issue (root ownership)
  - Fixed port mismatch (51413 vs 47528)
  - Confirmed no ISP throttling in Poland
  - Achieved 55 MB/s without VPN vs 15 MB/s with VPN
