# Home NAS Infrastructure

Proxmox home NAS with Ubuntu VMs and Docker containers, managed via Infrastructure as Code.

**Components:**

- **Terraform/OpenTofu**: Proxmox VM provisioning (main.tf, storage.tf)
- **Ansible**: Proxmox configuration, VM template creation, container deployment (playbooks/, inventory.yml)

## Project Structure

```
terraform/          - OpenTofu infrastructure (VM provisioning)
ansible/            - Ansible playbooks and inventory
  playbooks/        - Configuration playbooks
  inventory.yml     - Host inventory
  secrets/          - sops-encrypted secrets
docs/               - Documentation
.github/workflows/  - CI validation
```

## Tech Stack

### Terraform/OpenTofu

**Version:** 1.11.5
**Provider:** Proxmox (bpg/proxmox)
**Purpose:** Provision VMs on Proxmox host

### Ansible

**Version:** 2.20.2 (ansible-core)
**Python:** 3.14.3
**Purpose:** Configure Proxmox, deploy containers

### Shared Tools

**Tool Management:** mise
**Linting:** tflint, ansible-lint, yamllint
**Security:** trivy
**Secrets:** sops + age

## Development Workflow

### Adding New Service (Typical Flow: Terraform → Ansible)

1. **Provision infrastructure** (if new VM needed):

   ```bash
   cd terraform
   # Add VM resource to main.tf
   tofu plan
   tofu apply
   ```

2. **Update Ansible inventory** (critical step):

   ```bash
   # Edit ansible/inventory.yml with new VM details
   # Verify inventory
   ansible-inventory -i ansible/inventory.yml --list
   ```

3. **Deploy service via Ansible**:

   ```bash
   cd ansible
   # Create/update playbook
   ansible-playbook -i inventory.yml playbooks/deploy-service.yml
   ```

4. **Update secrets if needed**:

   ```bash
   sops ansible/secrets/secrets.yaml
   # Add secrets, save encrypted
   ```

### Validation Workflow

Always run before apply:

```bash
# Terraform dry-run
cd terraform && tofu plan

# Ansible check mode
cd ansible && ansible-playbook -i inventory.yml playbooks/deploy.yml --check

# NixOS dry-run
nixos-rebuild dry-run --flake .#media-services --target-host root@media-services
```

## Tool Selection Matrix

Use this decision matrix to choose the right tool:

### Hard Requirements (Auto-Select)

| Requirement                          | Tool          |
|:-------------------------------------|:--------------|
| Provision new Proxmox VM             | **Terraform** |
| Modify VM resources (CPU, RAM, disk) | **Terraform** |
| Configure Proxmox host itself        | **Ansible**   |
| Deploy Docker containers             | **Ansible**   |
| Configure VM OS/packages             | **Ansible**   |
| Manage secrets                       | **sops**      |

### Soft Criteria (When Multiple Options)

**Scenario: Configure service on VM**

- [+3 pts] Service is containerized → **Ansible** (Docker Compose)
- [+2 pts] Service is system-level (systemd, firewall) → **Ansible**
- [+1 pt] Service needs frequent updates → **Ansible**

**Scenario: Update VM configuration**

- [+3 pts] VM resource changes (CPU, RAM, disk) → **Terraform**
- [+2 pts] One-time setup task → **Ansible**
- [+1 pt] Temporary change/test → **Ansible** (easier rollback)

## Chain of Verification (Validation Pattern)

For infrastructure changes, use two-phase validation:

### Phase 1: Static Validation (CI)

Run locally before commit:

```bash
# Terraform validation
cd terraform
tflint --recursive --format compact
tofu fmt -check -recursive
tofu init -backend=false
tofu validate

# Ansible validation
cd ansible
yamllint ansible/
ansible-lint ansible/playbooks/
for playbook in playbooks/*.yml; do
  ansible-playbook --syntax-check "$playbook"
done
```

### Phase 2: Runtime Verification (Dry-Run)

Before actual apply:

```bash
# Terraform plan review
cd terraform
tofu plan  # Review changes carefully

# Ansible check mode
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy.yml --check --diff
```

**Critical:** Both phases must pass. Never skip dry-run.

**Confidence Levels:**

- **High:** CI + dry-run both pass, changes reviewed
- **Medium:** CI passes, dry-run not applicable
- **Low:** Manual changes, no validation possible

## Secrets Management

All secrets centralized in sops-encrypted file.

**Location:** `ansible/secrets/secrets.yaml`

**Edit:**

```bash
sops ansible/secrets/secrets.yaml
```

**Decrypt to env var:**

```bash
# Example: extract specific secret
export SECRET_VALUE=$(sops -d --extract '["key"]' ansible/secrets/secrets.yaml)
```

**Ansible usage:**

```yaml
# In playbook
vars:
  secret_value: "{{ lookup('env', 'SECRET_NAME') }}"
```

**Age key:** Derived from Proxmox SSH host key.

**Critical:** Never commit unencrypted secrets. Always use sops.

## Infrastructure State

### Terraform State

**Location:** Local (terraform/terraform.tfstate)

**Warning:** State managed locally. Avoid concurrent applies.

**Backup before risky changes:**

```bash
cp terraform/terraform.tfstate terraform/terraform.tfstate.backup
```

## Quality Gates

Before committing:

- [ ] `tofu fmt -check -recursive` passes
- [ ] `tofu validate` passes
- [ ] `tflint --recursive` passes
- [ ] `yamllint ansible/` passes
- [ ] `ansible-lint ansible/playbooks/` passes
- [ ] Playbook syntax checks pass
- [ ] Trivy security scan passes (CI only)
- [ ] Dry-run reviewed and approved

**Commands:**

```bash
# Terraform
cd terraform
tflint --recursive --format compact
tofu fmt -check -recursive
tofu init -backend=false && tofu validate

# Ansible
yamllint ansible/
ansible-lint ansible/playbooks/
cd ansible && for playbook in playbooks/*.yml; do ansible-playbook --syntax-check "$playbook"; done
ansible-inventory -i ansible/inventory.yml --list > /dev/null

# Security (requires docker)
trivy config --severity CRITICAL,HIGH --exit-code 1 terraform/
```

## Common Commands

### Terraform/OpenTofu

```bash
# Validate and plan
cd terraform
tofu init
tofu plan

# Apply changes
tofu apply

# Format code
tofu fmt -recursive

# Lint
tflint --recursive
```

### Ansible

```bash
# Validate inventory
ansible-inventory -i ansible/inventory.yml --list

# Run playbook
cd ansible
ansible-playbook -i inventory.yml playbooks/deploy-containers.yml

# Check mode (dry-run)
ansible-playbook -i inventory.yml playbooks/deploy.yml --check --diff

# Syntax check
ansible-playbook --syntax-check playbooks/playbook.yml

# Lint
ansible-lint playbooks/
yamllint ansible/
```

### Secrets

```bash
# Edit secrets
sops ansible/secrets/secrets.yaml

# View decrypted (read-only)
sops -d ansible/secrets/secrets.yaml

# Extract specific value
sops -d --extract '["key"]["subkey"]' ansible/secrets/secrets.yaml
```

## Output Templates

### Terraform Resource Template (Proxmox VM)

```hcl
resource "proxmox_virtual_environment_vm" "example_vm" {
  name        = "example-vm"
  description = "Description of VM purpose"
  tags        = ["ubuntu", "production"]

  node_name = "pve"
  vm_id     = 200  # Unique ID

  clone {
    vm_id = 9001  # ubuntu-template
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 8192
  }

  agent {
    enabled = true
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 20
  }

  disk {
    datastore_id = "tank-vms"
    interface    = "scsi0"
    size         = 32
  }
}
```

### Ansible Playbook Template

```yaml
---
# ansible/playbooks/example-playbook.yml
- name: Configure example service
  hosts: custom-workloads
  become: true

  vars:
    service_port: 8080

  tasks:
    - name: Ensure Docker is installed
      ansible.builtin.package:
        name: docker.io
        state: present

    - name: Deploy service container
      community.docker.docker_container:
        name: example-service
        image: "example/service:latest"
        state: started
        restart_policy: unless-stopped
        ports:
          - "{{ service_port }}:8080"
        volumes:
          - /data/example:/data
        env:
          CONFIG_PATH: /data/config.yml

    - name: Verify service is running
      ansible.builtin.uri:
        url: "http://localhost:{{ service_port }}/health"
        status_code: 200
      retries: 5
      delay: 3
```

## Anti-Patterns

**AVOID:**

- ❌ Forgetting to update Ansible inventory after Terraform VM changes → Deployments fail
- ❌ Manual Proxmox changes outside Terraform → State drift, apply failures
- ❌ Committing unencrypted secrets to git → Security breach
- ❌ Skipping dry-run/plan before apply → Unexpected destructive changes
- ❌ Applying Terraform without reviewing plan → Accidental VM deletion
- ❌ Manual VM changes without updating Terraform/Ansible → Config drift
- ❌ Concurrent Terraform applies → State conflicts
- ❌ Ignoring lint/validation errors → Syntax errors at apply time

**REASON:** Infrastructure mistakes are costly. State drift causes failures, secrets leaks cause breaches, skipped validation causes outages.

## Proxmox-Specific Notes

**Host:** AOOSTAR WTR MAX (AMD R7 Pro 8845HS)
**Address:** 192.168.0.101

**Storage Pools:**

- `tank-vms` (NVMe): VM disks
- `tank-media` (RAIDZ1): Media storage
  - Shared to media-services VM via VirtioFS (not NFS)
  - Single dataset (no child datasets) to support hardlinks

**VMs:**

- `media-services` (192.168.20.191): Ubuntu, Jellyfin stack (VLAN 20, 40)
  - VirtioFS mount: `/tank-media/data` → `/data` (supports hardlinks)
- `infrastructure` (192.168.10.222): Ubuntu, Caddy reverse proxy (VLAN 10, 30)
- `custom-workloads` (192.168.20.106): Ubuntu, Docker containers (VLAN 20)

**GPU Passthrough:** AMD 780M iGPU → media-services VM

**VM Storage Sharing:**

- **VirtioFS** (9p) for KVM VMs - supports hardlinks, required for Sonarr/Radarr
- **NOT NFS** - NFS breaks hardlinks across mounts
- **Single ZFS dataset** - child datasets create filesystem boundaries breaking hardlinks

## Extensibility

Add sections as infrastructure evolves:

- New VMs (add to terraform/, ansible/inventory.yml)
- New services (add Ansible playbooks or Docker Compose files)
- New secrets (edit ansible/secrets/secrets.yaml with sops)
- Monitoring/alerting integration
- Backup automation

Follow section structure above. Keep concrete and actionable.

See `.claude/skills/claude-md-gen/customization-guide.md` for:

- Adding new infrastructure patterns
- Customizing templates
- Extending validation workflows
