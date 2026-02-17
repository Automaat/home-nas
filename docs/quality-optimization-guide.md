# Quality Optimization Guide - Jellyfin Media Stack

Comprehensive guide to achieve maximum streaming quality with AMD 780M GPU transcoding and TRaSH-Guides quality profiles.

## Overview

**Goal:** Acquire high-quality content (H.265 preferred), enable direct play where possible, fallback to AMD GPU transcoding when needed.

**Key Decisions:**
- **Codec:** H.265/HEVC (50% smaller than H.264, better AMD encoder support)
- **Quality Tiers:** 1080p Remux > H.265 1080p > 4K (pre-encode 1080p copies)
- **Transcoding:** Direct play first, AMD VA-API fallback
- **Profiles:** TRaSH-Guides community standards

## Phase 1: Jellyfin AMD GPU Configuration

### 1.1 Verify GPU Availability

**SSH to media-services VM:**

```bash
ssh root@192.168.20.191
```

**Check GPU devices:**

```bash
ls -la /dev/dri/
# Expected output:
# drwxr-xr-x  3 root root         100 date time .
# drwxr-xr-x 20 root root        4400 date time ..
# drwxr-xr-x  2 root root          80 date time by-path
# crw-rw----  1 root video  226,   0 date time card0
# crw-rw----  1 root render 226, 128 date time renderD128
```

**Verify jellyfin user in render/video groups:**

```bash
docker exec jellyfin id
# Expected: uid=1000 gid=1000 groups=1000,44(video),109(render)
```

**If groups missing, add to Jellyfin container:**

Edit `/opt/media-stack/docker-compose.yml` on VM:

```yaml
jellyfin:
  image: lscr.io/linuxserver/jellyfin:10.11.6
  container_name: jellyfin
  group_add:
    - "44"    # video group
    - "109"   # render group
  # ... rest of config
```

Then restart:

```bash
docker compose -f /opt/media-stack/docker-compose.yml up -d jellyfin
```

### 1.2 Enable VA-API in Jellyfin

**Access Jellyfin WebUI:**

```bash
open http://192.168.20.191:8096
```

**Navigate to:** Dashboard → Playback → Transcoding

**Settings:**

1. **Hardware acceleration:** Video Acceleration API (VA-API)
2. **VA-API Device:** `/dev/dri/renderD128`
3. **Enable hardware decoding for:**
   - [x] H264
   - [x] HEVC
   - [x] VC1
   - [ ] VP9 (AMD 780M limited support)
   - [ ] AV1 (not supported on RDNA3 yet)
4. **Enable hardware encoding for:**
   - [ ] H264 (AMD encoder poor quality - avoid)
   - [x] HEVC (AMD HEVC encoder acceptable)
5. **Hardware encoding options:**
   - Encoding preset: Auto
   - Hardware encoding quality: Auto (50-70 recommended)
6. **Throttle transcodes:** Enabled (prevents overheating)
7. **Segment keep:** 5 (default)

**Streaming quality:**
- Internet streaming bitrate limit: 70% of upload speed
  - Example: 100 Mbps upload → set to 70 Mbps
  - Prevents buffering for other services

**Save changes.**

### 1.3 Test GPU Transcoding

**Upload test video:**

```bash
# From local machine
scp ~/test-video.mkv root@192.168.20.191:/data/media/movies/
```

**Or use existing media if available.**

**Trigger transcode:**

1. Open Jellyfin web player
2. Play video
3. Click settings icon (gear) during playback
4. Select lower quality/resolution than source
5. Force transcode by selecting incompatible codec

**Monitor GPU usage (in VM SSH session):**

```bash
watch -n1 'cat /sys/class/drm/card0/device/gpu_busy_percent'
# Should show >0% during transcoding
# Typical: 20-40% for 1080p H.264→H.265 transcode
```

**Check Jellyfin transcoding logs:**

```bash
docker exec jellyfin cat /config/log/log*.log | grep -i vaapi
# Should show: "VA-API device initialized"
# Should NOT show: "Failed to initialize VAAPI"
```

**If GPU not working, see Troubleshooting section.**

## Phase 2: Sonarr/Radarr Quality Profiles (TRaSH-Guides)

### 2.1 Understanding TRaSH-Guides

**TRaSH-Guides provide:**
- Community-vetted quality profiles
- Custom formats for fine-grained release scoring
- Automated preference management

**Profiles available:**
- **HD Bluray + WEB:** Mix of Remux/Bluray and WEB-DL releases
- **UHD Bluray + WEB:** 4K releases with HDR preference
- **Anime:** Optimized for anime releases (fansubbing groups)

**Official docs:** https://trash-guides.info/

### 2.2 Radarr Quality Profile Configuration

**Access Radarr:** http://192.168.20.191:7878

#### Option A: Manual Configuration (Recommended for Learning)

**Settings → Profiles → Add Profile**

**Profile Name:** HD-1080p (TRaSH)

**Allowed Qualities (in preference order, top = most preferred):**

1. Bluray-1080p Remux (uncheck if storage limited)
2. Bluray-1080p
3. WEBDL-1080p
4. WEBRip-1080p
5. HDTV-1080p (lowest priority)

**Quality Cutoff:** Bluray-1080p (or Remux if enabled)

**Minimum Custom Format Score:** 0
**Upgrade Until Custom Format Score:** 10000
**Upgrade Until Quality:** Bluray-1080p Remux

**Settings → Custom Formats → Add Custom Format**

**Key formats to add (from TRaSH-Guides):**

1. **BR-DISK** (score: -10000) - Avoid unprocessed Bluray folders
2. **LQ** (score: -10000) - Avoid low-quality releases (CAM, TS, etc.)
3. **x265 (HD)** (score: -10000) - Avoid x265 at 1080p (quality issues)
4. **3D** (score: -10000) - Avoid 3D releases (if not wanted)
5. **Remux Tier 01** (score: 1900) - Top-tier remux groups
6. **Remux Tier 02** (score: 1850) - Mid-tier remux groups
7. **WEB Tier 01** (score: 1800) - Top WEB-DL groups (FLUX, NTb, etc.)
8. **WEB Tier 02** (score: 1750) - Mid WEB-DL groups
9. **PROPER/REPACK** (score: 5) - Prefer fixed releases

**Custom format JSON:**

TRaSH-Guides provides JSON for each format:
https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/

**Example (BR-DISK avoidance):**

```json
{
  "name": "BR-DISK",
  "includeCustomFormatWhenRenaming": false,
  "specifications": [
    {
      "name": "avc/vc-1 and Bluray Disk",
      "implementation": "ReleaseTitleSpecification",
      "negate": false,
      "required": true,
      "fields": {
        "value": "^((?=.*\\b(AVC|VC-?1)\\b)(?=.*\\b(CEE|BDMV|BD(?![ .])[ .-]?(25|50|ISO|MUX)|BD66|BD100|Bluray|(?<!HD[ .-])BD)\\b)).*"
      }
    }
  ]
}
```

**Quick import via Radarr API (advanced):**

```bash
# Download TRaSH-Guides collection
curl https://raw.githubusercontent.com/TRaSH-Guides/Guides/master/docs/json/radarr/cf/br-disk.json -o /tmp/br-disk.json

# Import to Radarr (replace API_KEY)
curl -X POST http://192.168.20.191:7878/api/v3/customformat \
  -H "X-Api-Key: YOUR_RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/br-disk.json
```

#### Option B: Automated via Recyclarr (Recommended for Scale)

**Recyclarr automates TRaSH-Guides sync.**

**Install on media-services VM:**

```bash
ssh root@192.168.20.191
cd /opt
wget https://github.com/recyclarr/recyclarr/releases/latest/download/recyclarr-linux-x64.tar.gz
tar -xzf recyclarr-linux-x64.tar.gz
chmod +x recyclarr
```

**Create config:**

```bash
cat > /opt/recyclarr.yml <<EOF
radarr:
  instance-1:
    base_url: http://localhost:7878
    api_key: YOUR_RADARR_API_KEY

    delete_old_custom_formats: true
    replace_existing_custom_formats: true

    quality_definition:
      type: movie

    quality_profiles:
      - name: HD-1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-1080p Remux
          until_score: 10000
        qualities:
          - name: Bluray-1080p Remux
          - name: Bluray-1080p
          - name: WEBDL-1080p
          - name: WEBRip-1080p

    custom_formats:
      - trash_ids:
          - ed38b889b31be83fda192888e2286d83  # BR-DISK
          - 90cedc1fea7ea5d11298bebd3d1d3223  # EVO (except WEB-DL)
          - ae9b7c9ebde1f3bd336a8cbd1ec4c5e5  # No-RlsGroup
          - 7357cf5161efbf8c4d5d0c30b4815ee2  # Obfuscated
          - 5c44f52a8714fdd79bb4d98e2673be1f  # Retags
          - b8cd450cbfa689c0259a01d9e29ba3d6  # 3D
          - 570bc9ebecd92723d2d21500f4be314c  # Remaster
          - eca37840c13c6ef2dd0262b141a5482f  # 4K Remaster
          - e0c07d59beb37348e975a930d5e50319  # DV HDR10
          - 9f6cbff8cfe4ebbc1bde14c7b7bec0de  # DV HLG
          - 0f12c086e289cf966fa5948eac571f44  # DV SDR
          - 923b6abef9b17f937fab56cfcf89e1f1  # DV (Disk)
          - f700d29429c023a5734505e77daeaea7  # DV (FEL)
          - 1f733af03141f068a540eec352589a89  # DV (Profile 7)
        quality_profiles:
          - name: HD-1080p
            score: -10000  # Avoid these

      - trash_ids:
          - 3a3ff47579026e76d6504ebea39390de  # Remux Tier 01
          - 9f98181fe5a3fbeb0cc29340da2a468a  # Remux Tier 02
          - e6715bba186870e6e34e4a5fc5f32c5f  # WEB Tier 01
          - 58790d4e2fdcd9733aa7ae68ba2bb503  # WEB Tier 02
          - e7718d7a3ce595f289bfee26adc178f5  # Repack/Proper
        quality_profiles:
          - name: HD-1080p

sonarr:
  instance-1:
    base_url: http://localhost:8989
    api_key: YOUR_SONARR_API_KEY

    delete_old_custom_formats: true
    replace_existing_custom_formats: true

    quality_definition:
      type: series

    quality_profiles:
      - name: WEB-1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
          until_score: 10000
        qualities:
          - name: Bluray-1080p
          - name: WEBDL-1080p
          - name: WEBRip-1080p

    custom_formats:
      - trash_ids:
          - 32b367365729d530ca1c124a0b180c64  # Bad Dual Groups
          - 82d40da2bc6923f41e14394075dd4b03  # No-RlsGroup
          - e1a997ddb54e3ecbfe06341ad323c458  # Obfuscated
          - 06d66ab109d4d2eddb2794d21526d140  # Retags
          - 1b3994c551cbb92a2c781af061f4ab44  # Scene
        quality_profiles:
          - name: WEB-1080p
            score: -10000

      - trash_ids:
          - d6819cba26b1a6508138d25fb5e32293  # WEB Tier 01
          - e6258996055b9fbab7e9cb2f75819294  # WEB Tier 02
          - 4d74ac4c4db0b64bff6ce0cffef99bf0  # UHD Bluray Tier 01
          - a58f517a70193f8e578056642178419d  # UHD Bluray Tier 02
        quality_profiles:
          - name: WEB-1080p
EOF
```

**Get API keys:**

```bash
# Radarr
docker exec radarr cat /config/config.xml | grep -oP '<ApiKey>\K[^<]+'

# Sonarr
docker exec sonarr cat /config/config.xml | grep -oP '<ApiKey>\K[^<]+'
```

**Update recyclarr.yml with API keys, then run:**

```bash
/opt/recyclarr sync
```

**Schedule daily sync (crontab):**

```bash
crontab -e
# Add:
0 3 * * * /opt/recyclarr sync >> /var/log/recyclarr.log 2>&1
```

### 2.3 Sonarr Quality Profile Configuration

**Access Sonarr:** http://192.168.20.191:8989

**Follow same pattern as Radarr:**

**Settings → Profiles → Add Profile**

**Profile Name:** WEB-1080p (TRaSH)

**Allowed Qualities:**

1. Bluray-1080p (optional, less common for TV)
2. WEBDL-1080p
3. WEBRip-1080p
4. HDTV-1080p

**Custom formats (via TRaSH-Guides):**

- **Bad Dual Groups** (score: -10000)
- **LQ** (score: -10000)
- **x265 (HD)** (score: -10000)
- **WEB Tier 01** (score: 1800)
- **WEB Tier 02** (score: 1750)

**Use Recyclarr config above for automation.**

### 2.4 Configure Quality Settings (File Size)

**Radarr: Settings → Quality**

**Adjust bitrate ranges per quality tier:**

TRaSH-Guides recommended ranges:

- **1080p Remux:** 30-80 GB (no limit)
- **1080p Bluray:** 6-15 GB
- **1080p WEB-DL:** 3-8 GB
- **1080p WEBRip:** 2-6 GB

**Radarr UI:**

Settings → Quality → Click quality name → Adjust Min/Max size

**Sonarr: Settings → Quality**

Per-episode file size ranges:

- **1080p WEB-DL:** 1.5-4 GB (45min episode)
- **1080p WEBRip:** 1-3 GB
- **HDTV-1080p:** 0.8-2 GB

## Phase 3: Optimize Jellyfin Playback

### 3.1 Client Compatibility Settings

**Dashboard → Playback → Streaming**

**Internet streaming bitrate limit:** 70 Mbps (adjust based on upload speed)

**Allow video playback that requires conversion without re-encoding:**
- Enabled (allows remuxing without transcoding)

**H264 encoding preset:** Fast (balance quality/speed)

**HEVC encoding preset:** Medium (AMD HEVC better quality)

### 3.2 Library Settings

**Dashboard → Libraries → Movies/TV → Edit**

**Enable:** Real-time monitoring (auto-detect new files)

**Chapter image extraction:** Disabled (saves disk space)

**Trickplay image extraction:** Enabled (preview thumbnails)

### 3.3 Configure Direct Play

**User Settings (per client):**

1. Settings → Playback
2. **Maximum streaming bitrate:** Auto (or match connection speed)
3. **Video quality:** Maximum
4. **Prefer fMP4-HLS container:** Disabled (prefer native formats)

**Verify direct play in Jellyfin Dashboard:**

Dashboard → Activity → Active Devices

During playback, should show:
- **Play Method:** DirectPlay (best)
- **Stream:** Direct (no transcoding)

If showing "Transcode", check:
- Client codec support (browser vs app)
- Network bandwidth
- Force direct play in client settings

## Phase 4: Testing & Verification

### 4.1 Test Sonarr/Radarr Quality Profiles

**Radarr test:**

1. Add movie (Settings → Add Movies → Search)
2. Select **HD-1080p** profile
3. Search for release
4. Verify results scored correctly:
   - Remux releases: high score (~1900)
   - WEB-DL Tier 01: ~1800
   - Low quality: negative score (hidden or bottom)
5. Manual search to verify scoring:
   - Interactive Search → View scores
   - Check custom format badges

**Sonarr test:** Same process with TV show

### 4.2 Test End-to-End Workflow

**Full workflow:**

1. **Request:** Add content via Jellyseerr or direct to Radarr
2. **Search:** Verify highest-quality release selected
3. **Download:** Monitor qBittorrent progress
4. **Import:** Check Radarr/Sonarr → Activity
5. **Verify quality:**

```bash
ssh root@192.168.20.191
mediainfo /data/media/movies/Movie\ Name\ (2024)/Movie.mkv | grep -E 'Format|Codec|Resolution|Bit rate'
```

6. **Play in Jellyfin:** Verify direct play (no transcode)
7. **Force transcode:** Lower quality → verify GPU usage

**Expected output (H.265 1080p):**

```
Format: Matroska
Codec: HEVC
Width: 1920 pixels
Height: 1080 pixels
Bit rate: 6-8 Mbps (for ~2 hour movie)
```

### 4.3 Monitor Quality Over Time

**Check average file sizes:**

```bash
ssh root@192.168.20.191

# Movies
find /data/media/movies -name "*.mkv" -exec du -h {} \; | sort -h | tail -20

# TV shows (per episode)
find /data/media/tv -name "*.mkv" -exec du -h {} \; | sort -h | tail -20
```

**Expected ranges:**

- **Movies (H.265 1080p):** 4-10 GB
- **TV episodes (H.265 1080p):** 1-3 GB
- **4K Remux movies:** 40-80 GB (if enabled)

**Quality consistency check:**

```bash
# Check codec distribution
find /data/media/movies -name "*.mkv" -exec mediainfo --Inform="Video;%Format%\n" {} \; | sort | uniq -c
# Expected: Majority HEVC (H.265)
```

## Phase 5: Advanced Optimization

### 5.1 Jellyfin Tone Mapping (HDR → SDR)

**For HDR content on non-HDR displays.**

**Dashboard → Playback → Transcoding**

**Tone mapping algorithm:** bt2390 (recommended)
**Tone mapping mode:** Auto
**Tone mapping peak:** 100 (SDR standard)

**AMD 780M support:** Limited (may fallback to software tone mapping)

### 5.2 Pre-Encode 4K to 1080p (Optional)

**If acquiring 4K remux, create 1080p versions to avoid heavy transcoding.**

**On media-services VM:**

```bash
#!/bin/bash
# /opt/scripts/pre-encode-4k.sh

INPUT="$1"
OUTPUT="${INPUT%.mkv}-1080p.mkv"

ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -i "$INPUT" \
  -map 0:v:0 -map 0:a -map 0:s? \
  -c:v hevc_vaapi -profile:v main -qp 28 \
  -vf 'format=nv12,hwupload,scale_vaapi=w=1920:h=1080' \
  -c:a copy \
  -c:s copy \
  "$OUTPUT"
```

**Usage:**

```bash
chmod +x /opt/scripts/pre-encode-4k.sh
/opt/scripts/pre-encode-4k.sh /data/media/movies/Movie\ 4K/Movie.mkv
```

**Warning:** Encoding takes 1-2 hours for 2-hour movie. Run overnight.

### 5.3 Network Performance Tuning

**For gigabit streaming:**

**On media-services VM:**

```bash
# Edit /etc/sysctl.conf
cat >> /etc/sysctl.conf <<EOF
# Network performance tuning
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 5000
EOF

sysctl -p
```

**Restart Docker networking:**

```bash
systemctl restart docker
```

## Troubleshooting

### GPU Transcoding Not Working

**Symptom:** CPU usage 100%, GPU 0%

**Diagnosis:**

```bash
ssh root@192.168.20.191

# Check GPU device
ls -la /dev/dri/
# Should show: card0, renderD128

# Check container can access GPU
docker exec jellyfin ls -la /dev/dri/
# Should match host

# Check VA-API working
docker exec jellyfin vainfo
# Expected: VAEntrypointVLD for HEVC/H264
```

**Fix 1: Verify driver:**

```bash
lspci -nnk -d 1002:
# Should show: Kernel driver in use: amdgpu
```

If not, reinstall driver:

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/setup-media-services-gpu.yml
```

**Fix 2: Add groups to container:**

Edit `/opt/media-stack/docker-compose.yml`:

```yaml
jellyfin:
  group_add:
    - "44"    # video
    - "109"   # render (find with: getent group render)
```

Redeploy:

```bash
docker compose -f /opt/media-stack/docker-compose.yml up -d jellyfin
```

**Fix 3: AMD 780M driver issues (RDNA3):**

AMD 780M has known LLVM issues on older kernels.

Check kernel version:

```bash
uname -r
# Need 6.5+ for full RDNA3 support
```

Upgrade if <6.5:

```bash
apt update
apt install linux-generic-hwe-24.04
reboot
```

### Poor Quality Despite High Bitrate

**Symptom:** Large files, but poor visual quality

**Cause:** Likely x265 1080p encode (known for banding/artifacts)

**Fix:** Adjust custom format to avoid x265 at 1080p

**Radarr: Settings → Custom Formats → Add**

**Name:** x265 (HD)

**Regex:**

```
/\b(x265|h265|hevc)\b/i
AND
/\b(1080p|1080i)\b/i
```

**Score:** -10000

**Apply to profile:** HD-1080p

### Direct Play Failing

**Symptom:** Jellyfin always transcodes, even on capable clients

**Check:**

1. **Client codec support:**
   - Web browser: Limited to H.264 (will transcode HEVC)
   - Jellyfin app (desktop/mobile): Full codec support
   - Recommendation: Use native apps for direct play

2. **Container format:**
   - MKV not supported in web browsers
   - MP4/M4V preferred for web compatibility
   - Radarr: Settings → Media Management → Standard Movie Format

3. **Audio codec:**
   - Web browsers: Limited to AAC/MP3
   - TrueHD/DTS requires transcoding
   - Consider audio downmix in Jellyfin: Dashboard → Playback → Allow audio that requires conversion

4. **Network bandwidth:**
   - Verify client connection speed
   - Jellyfin auto-selects lower bitrate if network slow
   - Check: Dashboard → Activity → Active streams → Bitrate

### Recyclarr Sync Failing

**Check logs:**

```bash
cat /var/log/recyclarr.log
```

**Common issues:**

- Wrong API key: Regenerate in Radarr/Sonarr
- Network timeout: Check container connectivity
- Format conflicts: `delete_old_custom_formats: true` to override

**Manual fix:**

```bash
/opt/recyclarr sync --debug
```

## Monitoring & Maintenance

### Regular Checks

**Weekly:**
- Review Jellyfin Dashboard → Activity (transcoding frequency)
- Check average file sizes (ensure not downloading low-quality)
- Review Radarr/Sonarr → Activity → Queue (stalled downloads)

**Monthly:**
- Update Recyclarr custom formats: `/opt/recyclarr sync`
- Review quality profile scores (TRaSH-Guides updates)
- Check GPU health: `sensors` (temperature <80°C under load)

**Quarterly:**
- Review storage usage: `zfs list tank-media/data`
- Audit acquired content quality (spot-check with mediainfo)
- Update quality profile preferences based on experience

### Metrics to Track

**Quality metrics:**

```bash
# Average movie file size
find /data/media/movies -name "*.mkv" -exec du -b {} \; | awk '{sum+=$1; count++} END {print sum/count/1024/1024/1024 " GB"}'

# Codec distribution
find /data/media -name "*.mkv" -exec mediainfo --Inform="Video;%Format%\n" {} \; | sort | uniq -c
```

**Target benchmarks:**
- H.265 1080p movies: 6-8 GB avg
- H.265 1080p TV episodes: 1.5-2.5 GB avg
- >80% HEVC codec usage
- <20% transcoding rate (check Jellyfin stats)

**GPU utilization:**

```bash
# Log GPU usage during playback
while true; do
  echo "$(date): $(cat /sys/class/drm/card0/device/gpu_busy_percent)%" >> /var/log/gpu-usage.log
  sleep 5
done
```

Target: <50% peak usage (headroom for multiple streams)

## Summary Checklist

**Phase 1: Jellyfin GPU Setup**
- [x] Verify /dev/dri/renderD128 exists
- [x] Enable VA-API in Jellyfin
- [x] Set HEVC hardware encoding
- [ ] Test transcode with GPU monitoring (pending content)

**Phase 2: Quality Profiles**
- [x] Created custom formats via API
- [x] Configure Radarr UHD/FHD Remux profiles
- [x] Configure Sonarr HD-1080p/Ultra-HD profiles
- [x] Adjusted file size ranges

**Phase 3: Jellyfin Optimization**
- [x] Set streaming bitrate limits (66 Mbps)
- [x] Enable direct play preferences
- [x] Configure client playback settings

**Phase 4: Testing**
- [ ] Test quality profile scoring (pending content)
- [ ] End-to-end workflow verification (pending content)
- [ ] Monitor file quality/sizes (pending content)

**Phase 5: Advanced (Optional)**
- [ ] Configure HDR tone mapping
- [ ] Setup 4K pre-encoding script
- [ ] Network performance tuning

## Configuration Summary (Completed)

**Jellyfin (192.168.20.191:8096)**
- Hardware acceleration: VA-API with /dev/dri/renderD128
- GPU groups: video (44), render (993)
- HEVC encoding enabled (AMD encoder)
- Bitrate limit: 66 Mbps (70% of 95 Mbps upload)

**Radarr (192.168.20.192:7878)**
- Custom formats created:
  - BR-DISK (score: -10000)
  - LQ (score: -10000)
  - x265 (HD) (score: -10000)
  - Repack/Proper (score: +5)
- Quality profiles configured:
  - UHD Remux (4K priority: 40-80GB)
  - FHD Remux (1080p priority: 20-50GB)

**Sonarr (192.168.20.192:8989)**
- Same custom formats applied
- HD-1080p profile configured
- Ultra-HD profile configured

**Next steps when adding content:**
1. Add via Jellyseerr or direct to Sonarr/Radarr
2. Verify quality profile scoring in search results
3. Monitor downloads - check file sizes match expected ranges
4. Test playback - verify direct play locally (no transcoding)
5. Force transcode to test GPU usage

**Done! Enjoy maximum quality streaming.**
