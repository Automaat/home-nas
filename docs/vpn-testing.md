# VPN Testing - Downloads Stack

## Test Without VPN

**Purpose:** Benchmark download speeds without VPN overhead.

### Disable VPN

Edit `ansible/docker-compose/downloads-stack.yml`:

```yaml
services:
  # gluetun:  # Comment out entire gluetun service
  #   image: qmcgaw/gluetun:v3.41.1
  #   ...

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:20.04.1
    container_name: qbittorrent
    # network_mode: container:gluetun  # Comment out
    ports:  # Add direct port exposure
      - 8080:8080
      - 6881:6881
      - 6881:6881/udp
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Amsterdam
      - WEBUI_PORT=8080
    volumes:
      - /data/qbittorrent/config:/config
      - /data/downloads:/data/downloads
    # depends_on:  # Comment out gluetun dependency
    #   gluetun:
    #     condition: service_healthy
    restart: unless-stopped
```

### Deploy

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
```

### Test

- WebUI: http://192.168.20.106:8080
- Add test torrent (Linux ISO, popular public torrent)
- Monitor speeds

## Revert to VPN

### Restore Configuration

Edit `ansible/docker-compose/downloads-stack.yml`:

```yaml
services:
  gluetun:  # Uncomment entire service
    image: qmcgaw/gluetun:v3.41.1
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - 8080:8080
      - 6881:6881
      - 6881:6881/udp
    environment:
      - VPN_SERVICE_PROVIDER=private internet access
      - OPENVPN_USER=p4386889
      - OPENVPN_PASSWORD=81jR3hv*kVUbqaV^arIz@72BX
      - SERVER_REGIONS=Netherlands
      - VPN_PORT_FORWARDING=on
      - OPENVPN_ENCRYPTION_PRESET=normal
      - FIREWALL_OUTBOUND_SUBNETS=192.168.20.0/24,192.168.40.0/24
      - UPDATER_PERIOD=24h
    volumes:
      - /data/gluetun:/gluetun
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "sh", "-c", "ping -c 1 1.1.1.1 || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 10s

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:20.04.1
    container_name: qbittorrent
    network_mode: container:gluetun  # Restore VPN routing
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Amsterdam
      - WEBUI_PORT=8080
    volumes:
      - /data/qbittorrent/config:/config
      - /data/downloads:/data/downloads
    depends_on:  # Restore dependency
      gluetun:
        condition: service_healthy
    restart: unless-stopped
```

**Key changes:**
1. Uncomment gluetun service
2. Restore `network_mode: container:gluetun`
3. Remove qbittorrent `ports` section
4. Restore `depends_on` block

### Deploy

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
```

### Verify

```bash
# Check containers running
ansible custom-workloads -i inventory.yml -m shell -a "docker ps | grep -E 'gluetun|qbittorrent'"

# Check VPN connection
ansible custom-workloads -i inventory.yml -m shell -a "docker exec gluetun wget -qO- https://ipinfo.io/ip"
```

Expected: IP from Netherlands (PIA VPN server).

## Quick Revert Commands

```bash
# Restore from git (if committed VPN config)
git checkout ansible/docker-compose/downloads-stack.yml

# Redeploy
cd ansible && ansible-playbook -i inventory.yml playbooks/deploy-containers.yml
```
