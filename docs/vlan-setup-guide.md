# Gradual VLAN Setup Guide

## Prerequisites

- Console access to Proxmox (monitor + keyboard OR IPMI)
- Current SSH access working
- Backup of important data

## Step-by-Step Execution

### Step 1: Backup current config

```bash
cd ~/sideprojects/home-nas/ansible
ansible-playbook -i inventory.yml playbooks/configure-vlans-gradual.yml --tags backup
```

**Expected:** Backup created at `/etc/network/interfaces.backup-vlan`

### Step 2: Check current config

```bash
ansible-playbook -i inventory.yml playbooks/configure-vlans-gradual.yml --tags check
```

**Expected:** Shows current network config, indicates VLANs not configured

### Step 3: Add VLAN awareness to bridge

```bash
ansible-playbook -i inventory.yml playbooks/configure-vlans-gradual.yml --tags vlan-bridge
```

**Expected:**

- Adds `bridge-vlan-aware yes` to vmbr0
- Uses `ifreload` (not full restart)
- Tests SSH connectivity
- Shows "SSH still working"

**If this fails:**

- Use console access
- Run rollback: `ansible-playbook -i inventory.yml playbooks/configure-vlans-gradual.yml --tags rollback`

**Verify manually:**

```bash
ssh root@192.168.0.101
bridge vlan show
# Should show vmbr0 with VLANs 10,20,30,40
```

### Step 4: Verify VLAN config

```bash
ansible-playbook -i inventory.yml playbooks/configure-vlans-gradual.yml --tags verify
```

**Expected:** Shows VLAN filtering enabled

### Step 5: Test with one VM (manual)

**Option A - Proxmox UI:**

1. Log in to Proxmox web UI
2. Select `custom-workloads` VM
3. Hardware → Network Device → Edit
4. Set VLAN Tag = `20`
5. OK → Reboot VM
6. SSH to VM: `ssh ubuntu@192.168.0.104`
7. Verify network works

**Option B - Command line:**

```bash
ssh root@192.168.0.101
qm set 104 -net0 virtio,bridge=vmbr0,tag=20
qm reboot 104

# Wait 30 seconds
ssh ubuntu@192.168.0.104  # Should work
```

**If VM loses connectivity:**

- Remove VLAN tag via Proxmox UI
- Or: `qm set 104 -net0 virtio,bridge=vmbr0`

### Step 6: Apply VLANs to all VMs (Terraform)

Once one VM works, update Terraform config:

```bash
cd ~/sideprojects/home-nas/terraform
tofu plan
# Review changes - should show VLAN tags being added
tofu apply
```

**Expected:**

- media-services: VLAN 20 (primary) + VLAN 40 (qBittorrent)
- infrastructure: VLAN 10 (management) + VLAN 30 (public)
- custom-workloads: VLAN 20

### Step 7: Verify all VMs

```bash
ssh root@192.168.0.102  # media-services
ssh root@192.168.0.103  # infrastructure
ssh ubuntu@192.168.0.104  # custom-workloads
```

All should work.

## Rollback

If anything goes wrong:

```bash
ansible-playbook -i inventory.yml playbooks/configure-vlans-gradual.yml --tags rollback
```

Or manually via console:

```bash
cp /etc/network/interfaces.backup-vlan /etc/network/interfaces
ifreload -a
```

## VLAN Assignment Reference

| VM               | Management (10) | Services (20) | Public (30) | Downloads (40) |
|:-----------------|:----------------|:--------------|:------------|:---------------|
| Proxmox host     | ✓ (untagged)    | -             | -           | -              |
| media-services   | -               | ✓             | -           | ✓              |
| infrastructure   | ✓               | -             | ✓           | -              |
| custom-workloads | -               | ✓             | -           | -              |

## Firewall (Future)

After VLANs stable, optionally add Proxmox firewall rules:

- Allow SSH on VLAN 10 only
- Allow services on respective VLANs
- Block inter-VLAN routing (except specific rules)

**Don't enable firewall until VLANs fully tested and working.**
