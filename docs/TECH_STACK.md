# Technology Stack: Learnings and Reference

This document captures the technology decisions, discoveries, and domain knowledge
accumulated while building this IaC project. It is intended as a reference for
anyone working with SUSE/openSUSE images on KVM/libvirt, especially in non-cloud
environments.

---

## Table of Contents

1. [Version Summary](#1-version-summary)
2. [First-Boot Provisioning Tools](#2-first-boot-provisioning-tools)
3. [SUSE/openSUSE Image Landscape](#3-suseopensuse-image-landscape)
4. [How Images Are Built (KIWI)](#4-how-images-are-built-kiwi)
5. [Cloud-Init in Non-Cloud Environments](#5-cloud-init-in-non-cloud-environments)
6. [IaC Tooling: OpenTofu + Libvirt Provider](#6-iac-tooling-opentofu--libvirt-provider)
7. [IP Discovery on Bridged Networks](#7-ip-discovery-on-bridged-networks)
8. [Post-Provisioning with Ansible](#8-post-provisioning-with-ansible)
9. [Python Tooling: uv](#9-python-tooling-uv)

---

## 1. Version Summary

Quick reference for all tool versions used in (or relevant to) this project.

| Tool / Component | Version in this project | Latest stable (as of Mar 2026) | Notes |
|---|---|---|---|
| **OpenTofu** | v1.6.0-alpha3 | v1.11.5 | Pre-release; upgrade recommended (see [§6](#6-iac-tooling-opentofu--libvirt-provider)) |
| **terraform-provider-libvirt** | v0.9.5 | v0.9.5 | Current latest release |
| **Ignition provider** | v2.7.0 | v2.7.0 | `community-terraform-providers/ignition` |
| **cloud-init** | (bundled in image) | 26.1 | Version depends on the OS image used |
| **Ignition spec** | v3.4.0 (in SLE Micro config) | v3.6.0 stable | v3.4.0 still supported; v3.5.0+ adds LUKS cex, Azure blob |
| **KIWI NG** | — | v10.2.45 | Used by openSUSE to build Minimal VM images |
| **ansible-core** | 2.20.3 | 2.20.3 (2.20.4rc1 pre-release) | Managed via uv and pyproject.toml |
| **Python** | 3.13 | 3.13.7 | Set via `.python-version`; managed by uv |
| **uv** | 0.10.8 | 0.10.11 | Python package/project manager |
| **libvirt** (KVM host) | 8.0.0 | — | Remote host: openSUSE Leap 15.x |
| **QEMU** (KVM host) | 6.2 | — | Remote host: openSUSE Leap 15.x |

---

## 2. First-Boot Provisioning Tools

Linux distributions use different tools to configure a system on its first boot.
The provisioning tool is not a user choice at deployment time — it is **baked into
the image at build time**. Choosing the right tool means choosing the right image.

### cloud-init

- **Origin:** Canonical (Ubuntu), now a cross-distro standard for cloud VMs.
- **Current version:** 26.1 (Feb 2026). Uses calendar-based versioning (YY.N).
- **Config format:** YAML (`#cloud-config`).
- **Datasources:** Cloud metadata services (EC2, GCE, Azure), NoCloud (local
  ISO or filesystem), ConfigDrive, and many others.
- **Capabilities:** User creation, SSH key injection, package installation,
  arbitrary commands (`runcmd`), disk resize, hostname, network config.
- **When to use:** Cloud VMs, or non-cloud environments with NoCloud ISO delivery.
- **SUSE images that include it:** `*-Cloud.qcow2` variants.

### Ignition

- **Origin:** CoreOS (now part of Red Hat/Fedora).
- **Current version:** Ignition v2.26.0 (application). Spec v3.6.0 is the
  latest stable; v3.7.0-experimental is in development. All stable specs from
  v3.0.0 through v3.6.0 are supported. SLE Micro images typically support up
  to v3.4.0 or v3.5.0 depending on the release.
- **Config format:** JSON (Ignition spec, typically v3.x). Usually generated from
  a higher-level format (Butane YAML for Fedora CoreOS, or the Terraform
  `ignition` provider's HCL data sources).
- **Delivery:** QEMU fw_cfg (`opt/com.coreos/config`), or a config device.
- **Capabilities:** Disk partitioning, filesystem creation, file writing, user
  creation, systemd unit management. Runs very early in boot (initrd).
- **When to use:** Immutable/container-optimized OS images (Fedora CoreOS,
  openSUSE MicroOS, SLE Micro).
- **Key difference from cloud-init:** Ignition is designed to run **once** and
  treats the system as immutable infrastructure. cloud-init can run on every boot.
- **Spec version history:**

  | Spec version | Ignition release | Notable additions |
  |---|---|---|
  | v3.0.0 | 2.0.0 | Initial v3 spec |
  | v3.1.0 | 2.3.0 | |
  | v3.2.0 | 2.7.0 | |
  | v3.3.0 | 2.11.0 | |
  | v3.4.0 | 2.15.0 | Used by SLE Micro 5.x/6.x |
  | v3.5.0 | 2.20.0 | LUKS cex (s390x), Azure blob support |
  | v3.6.0 | 2.26.0 | Latest stable |

### Combustion

- **Origin:** SUSE (openSUSE/SLE Micro).
- **Config format:** A shell script (`combustion/script`) on a config device.
- **Delivery:** USB drive, ISO, or disk partition labeled `ignition` or `combustion`.
- **Capabilities:** Arbitrary shell commands during first boot. Simpler than
  Ignition — no JSON spec to learn, just write a bash script.
- **When to use:** SLE Micro and openSUSE MicroOS deployments where you want
  simple scripted provisioning without writing Ignition JSON.
- **Relationship with Ignition:** On SLE Micro/MicroOS, Combustion and Ignition
  can coexist on the same config device. Ignition runs first (in initrd),
  Combustion runs after (during first boot). Combustion can complement Ignition
  or replace it entirely.

### JeOS Firstboot

- **Origin:** SUSE.
- **Config format:** Interactive console wizard (locale, keyboard, timezone,
  root password, registration).
- **When to use:** Manual/interactive deployments. Not suitable for automated IaC.
- **SUSE images that include it:** `*-kvm-and-xen.qcow2`, `*-VMware.vmdk`,
  `*-MS-HyperV.vhdx` variants, and as fallback on SLE Micro when no config
  device is present.

### Comparison Matrix

| Feature | cloud-init | Ignition | Combustion | JeOS Firstboot |
|---|---|---|---|---|
| Config format | YAML | JSON | Shell script | Interactive |
| Runs when | Every boot (configurable) | Once (initrd) | Once (first boot) | Once (first boot) |
| Automation-friendly | Yes | Yes | Yes | No |
| User creation | Yes | Yes | Yes (scripted) | Yes (interactive) |
| Package install | Yes | No | Yes (scripted) | No |
| Disk management | Resize only | Full (partition, format, mount) | Yes (scripted) | No |
| Cloud metadata | Yes (native) | No | No | No |
| Non-cloud delivery | NoCloud ISO | fw_cfg / config device | Config device | Console |

---

## 3. SUSE/openSUSE Image Landscape

### openSUSE Tumbleweed — Minimal VM Images

All Minimal VM images are built from a single KIWI description
(`Minimal.kiwi`) using different profiles. The profile determines which
packages are installed, which filesystem is used, and which first-boot tool
is available.

| Image variant | Filename pattern | First-boot tool | Filesystem | Bootloader |
|---|---|---|---|---|
| **Cloud** | `*-Cloud.qcow2` | cloud-init | XFS | GRUB2 |
| **KVM and XEN** | `*-kvm-and-xen.qcow2` | JeOS Firstboot | Btrfs | GRUB2 |
| **KVM sdboot** | `*-kvm-and-xen-sdboot.qcow2` | JeOS Firstboot | Btrfs | systemd-boot |
| **VMware** | `*-VMware.vmdk` | JeOS Firstboot | Btrfs | GRUB2 |
| **MS HyperV** | `*-MS-HyperV.vhdx.xz` | JeOS Firstboot | Btrfs | GRUB2 |

**Key takeaway:** For automated KVM deployments, the `*-Cloud.qcow2` image is
the only viable option — it's the only variant with a non-interactive first-boot
tool. The `*-kvm-and-xen.qcow2` image is designed for interactive use.

### openSUSE MicroOS

Container/edge-optimized OS with immutable root filesystem (read-only Btrfs)
and transactional updates.

| Image variant | Filename pattern | First-boot tool |
|---|---|---|
| **KVM and XEN** | `*-kvm-and-xen.qcow2` | Combustion (+ optionally Ignition) |
| **OpenStack-Cloud** | `*-OpenStack-Cloud.qcow2` | cloud-init |
| **Hardware** | `*-RaspberryPi.raw.xz`, `*-Pine64.raw.xz` | Combustion |

### SLE Micro (SUSE Linux Micro)

Commercial immutable OS for edge and containerized workloads.

- **First-boot tools:** Ignition + Combustion.
- **Config device:** Labeled `ignition` (supports both Ignition and Combustion)
  or `combustion` (Combustion only).
- **Ignition config path:** `ignition/config.ign` (JSON, spec v3.4.0 or later;
  SLE Micro 6.x supports at least up to v3.4.0, check your specific version's
  release notes for v3.5.0 support).
- **Combustion config path:** `combustion/script` (shell script).
- **Execution order:** Ignition first (initrd), then Combustion (first boot).
- **Fallback:** JeOS Firstboot wizard when no config device is present.

### The Selection Rule

The provisioning tool is not a preference — it is determined by the image:

```
Image filename contains "-Cloud"     → cloud-init is installed    → use cloud-init
Image filename contains "-kvm-and-xen" (Tumbleweed) → JeOS Firstboot → interactive only
Image is MicroOS KVM                  → Combustion/Ignition       → use those
Image is SLE Micro                    → Ignition + Combustion     → use those
```

You cannot use Ignition on a cloud-init image or cloud-init on an Ignition image.
The image simply does not have the other tool installed. This project originally
attempted to use Ignition with a `*-Cloud.qcow2` image — the VM booted but
cloud-init blocked waiting for a metadata service, so networking was never
configured.

---

## 4. How Images Are Built (KIWI)

All openSUSE Tumbleweed Minimal VM images are built using
[KIWI NG](https://osinside.github.io/kiwi/) (current version: v10.2.45),
SUSE's OS image build system.

### Build source

The KIWI description file and supporting scripts live on the Open Build Service:

```
Project:  Virtualization:Appliances:Images:openSUSE-Tumbleweed
Package:  kiwi-templates-Minimal
Files:    Minimal.kiwi, config.sh, editbootinstall_*.sh, ...
```

### How profiles work

`Minimal.kiwi` defines multiple `<profile>` elements. Each profile is a
namespace for additional settings applied by KIWI in addition to the default
settings. A profile specifies:

- **Packages:** Which packages to install (e.g., the `Cloud` profile adds
  `cloud-init` and `xfsprogs`; the `kvm-and-xen` profile does not).
- **Filesystem:** `Cloud` uses XFS, others use Btrfs.
- **Disk format:** qcow2, vmdk, vhdx, etc.
- **Bootloader:** GRUB2 or systemd-boot.

Profiles can also inherit from other profiles via the `<requires>` sub-element,
and can be selected at build time via the command line:

```bash
kiwi-ng --profile Cloud system build ...
```

### How cloud-init gets activated

The `config.sh` script runs during image build. It checks if `cloud-init` is
installed and, if so, enables the cloud-init services:

```bash
if rpm -q cloud-init; then
    systemctl enable cloud-init
    systemctl enable cloud-config
    systemctl enable cloud-final
fi
```

This is what makes the Cloud image "cloud-init capable" — the package is
installed by the profile, and the services are enabled by `config.sh`. Other
profiles simply don't install cloud-init, so the `if` block is skipped.

### Implications for IaC

- The provisioning tool is a build-time decision, not a deployment-time choice.
- To change the provisioning tool, you must use a different image (or build a
  custom one with KIWI).
- When selecting an image for automated deployment, always verify which
  first-boot tool is included by checking the image variant name.

---

## 5. Cloud-Init in Non-Cloud Environments

cloud-init was designed for cloud environments where instance metadata is served
by a cloud provider's metadata service (e.g., `http://169.254.169.254`). In
non-cloud environments (bare KVM/libvirt), there is no metadata service. Without
a datasource, cloud-init blocks during boot, waiting for metadata — the VM runs
but networking is never configured.

### The NoCloud Datasource

The standard solution for non-cloud environments is the **NoCloud** datasource.
cloud-init recognizes a block device (ISO, partition, or USB) with the volume
label `cidata` as a local metadata source. The `fs_label` for NoCloud defaults
to `cidata` and is configurable.

The ISO must contain at minimum:

| File | Purpose | Format |
|---|---|---|
| `user-data` | System configuration | YAML (`#cloud-config`) |
| `meta-data` | Instance identity | YAML (instance-id, local-hostname) |

Optional files: `network-config` (v1 or v2 format), `vendor-data`.

There are two methods for creating the NoCloud data source:

1. **ISO 9660 image** (used in this project):
   ```bash
   genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
   # or equivalently:
   mkisofs -output seed.iso -volid cidata -joliet -rock user-data meta-data
   ```

2. **VFAT filesystem image** (alternative):
   ```bash
   truncate --size 2M seed.iso
   mkfs.vfat -n cidata seed.iso
   mcopy -oi seed.iso user-data meta-data ::
   ```

The `-volid cidata` / `-n cidata` label is critical — cloud-init searches for
this exact label.

### Delivery in this project

1. OpenTofu writes `user-data` and `meta-data` to a local `.cloudinit/` directory.
2. `mkisofs` builds the ISO locally.
3. `scp` uploads the ISO to the KVM host at `/var/lib/libvirt/images/<hostname>-cidata.iso`.
4. The ISO is attached to the domain as a CDROM disk (SATA bus, `device = "cdrom"`).
5. On first boot, cloud-init detects the `cidata` volume, reads config, creates
   users, installs packages (including `qemu-guest-agent`), and configures networking.

### Why not `libvirt_cloudinit_disk`?

The provider's `libvirt_cloudinit_disk` resource has the same bug as
`libvirt_ignition` (PROVIDER_ISSUES.md, Issue 2): it writes the ISO to a local
`/tmp/` path and passes that local path to the remote libvirt daemon. For
`qemu+ssh://` connections, the file doesn't exist on the KVM host and the
domain fails to start. We build and upload the ISO ourselves as a workaround.

---

## 6. IaC Tooling: OpenTofu + Libvirt Provider

### OpenTofu

This project uses [OpenTofu](https://opentofu.org/) v1.6.0-alpha3 instead of
HashiCorp Terraform. OpenTofu is the open-source fork of Terraform, created
after HashiCorp changed Terraform's license to BSL. For our purposes, the two
are interchangeable — same HCL syntax, same provider ecosystem, same state format.

Binary location: `/home/michelepa/bin/tofu`

> **Note on versioning:** This project runs **v1.6.0-alpha3**, which was an early
> pre-release of the very first OpenTofu version. The current stable release is
> **v1.11.5** (Mar 2026). Significant features have been added since v1.6.0,
> including:
>
> - **v1.7.0:** State encryption, removed block, `templatestring` function,
>   `loopvar` for loops
> - **v1.8.0:** Provider-defined functions, `.tofu` file extension support for
>   OpenTofu-specific config, `override_resource` for testing
> - **v1.9.0:** Input variable validation improvements
> - **v1.10.0:** Additional improvements and bug fixes
> - **v1.11.0:** Ephemeral resources & write-only attributes (values that exist
>   only in memory during a phase and are never persisted to state), `enabled`
>   meta-argument (alternative to `count` for zero-or-one instances)
>
> Upgrading to a stable release is recommended. The v1.6.0-alpha3 binary works
> for the current use case but lacks years of bug fixes and new features.

### The libvirt provider

[`dmacvicar/libvirt`](https://github.com/dmacvicar/terraform-provider-libvirt)
is a community Terraform/OpenTofu provider that manages libvirt resources
(domains, volumes, networks, etc.) via the libvirt API.

**Version history in this project:**

| Version | Status | Notes |
|---|---|---|
| v0.7.1 | Original | Stable, well-documented, widely used |
| v0.9.5 | Current (also latest release) | Complete schema rewrite, many breaking changes |

The v0.7.1 → v0.9.5 migration required rewriting every resource in `main.tf`.
See `PROVIDER_MIGRATION.md` for the full mapping and `PROVIDER_ISSUES.md` for
bugs discovered during migration.

The v0.9.x line follows the
[libvirt domain XML schema](https://libvirt.org/formatdomain.html) much more
closely than v0.7.x, resulting in more verbose but structurally accurate HCL.
However, the read-back functions have numerous bugs (see PROVIDER_ISSUES.md,
Issue 7) causing "Inconsistent result after apply" errors across many attributes.

#### Declaring a virtio-serial channel (guest agent) in v0.9.5

The provider does **not** automatically add a virtio-serial channel for the
QEMU guest agent — it must be declared explicitly in `devices.channels`.
The correct HCL schema for v0.9.5 is:

```hcl
devices = {
  channels = [
    {
      source = {
        unix = {}  # libvirt auto-assigns the socket path under /var/lib/libvirt/qemu/channel/
      }
      target = {
        virt_io = {
          name = "org.qemu.guest_agent.0"
        }
      }
    }
  ]
}
```

A common mistake (sourced from outdated docs or v0.7.x patterns) is to use
flat `type` and `target.type` strings — this is **wrong** for v0.9.5:

```hcl
# WRONG — do not use in v0.9.5:
channels = [{ type = "unix"; target = { type = "virtio"; name = "..." } }]
```

When the channel is correctly declared, `virsh dumpxml` will show
`<target ... state='connected'/>` once the guest agent inside the VM has
started, confirming end-to-end communication is established.

### The Ignition Terraform provider

This project also uses the
[`community-terraform-providers/ignition`](https://github.com/community-terraform-providers/terraform-provider-ignition)
provider (v2.7.0) which provides HCL data sources for generating Ignition JSON
configs. While the project currently uses cloud-init (not Ignition) for the
Tumbleweed Cloud image, the Ignition provider remains in the lock file from
earlier experimentation with MicroOS/SLE Micro images.

### Remote `qemu+ssh://` gotchas

The provider connects to a remote KVM/libvirt host via:

```
qemu+ssh://root@qesap-kvm1.qe.prg3.suse.org/system
```

This is a supported libvirt connection URI, but several provider resources
assume the client and host are the same machine:

- **`libvirt_ignition`** — writes ignition file to local `/tmp/`, passes local
  path to remote libvirt. Broken.
- **`libvirt_cloudinit_disk`** — same issue.
- **`libvirt_combustion`** — likely the same issue (not tested).
- **Volume URLs** — `create.content.url` works correctly because the provider
  streams the download through the libvirt API, which fetches the URL from the
  remote host.

**Workaround pattern:** For any resource that writes a file and references it
on the host, bypass the provider resource and use `local-exec` provisioners
with `scp` to upload files directly to the remote host.

### State management

OpenTofu state (`terraform.tfstate`) tracks all managed resources. Key
considerations:

- After failed applies, resources may be **tainted** in state but still exist
  on the KVM host (see PROVIDER_ISSUES.md, Issue 4).
- `make clean` handles orphaned domains and state inconsistencies.
- The state file is `.gitignore`d and lives only on the developer's machine.

---

## 7. IP Discovery on Bridged Networks

### The problem

On libvirt-managed NAT networks, libvirt runs dnsmasq and knows which IPs it
assigned via DHCP leases. The provider can query these leases to discover the
guest's IP.

On **bridged** networks (our setup uses `br0`), the DHCP server is external
(the corporate network's DHCP). Libvirt has no visibility into these leases.

The result:
- `virsh domifaddr <domain>` (default source: `lease`) returns nothing.
- `virsh domifaddr <domain> --source arp` may work but is unreliable (stale
  ARP entries, timing issues).
- The provider's `wait_for_ip = {}` relies on these mechanisms and fails with
  a 300-second timeout on bridged networks.

### The solution: QEMU Guest Agent

The **QEMU Guest Agent** (`qemu-guest-agent`) runs inside the VM and
communicates with the hypervisor via a virtio serial channel. It can report
the guest's network configuration directly:

```bash
virsh domifaddr <domain> --source agent
```

This is the only reliable method for IP discovery on bridged networks.

### The dependency chain

For this to work, the following must happen in order:

1. The domain XML must contain a `<channel type="unix">` virtio-serial device
   (declared via `devices.channels` in `main.tf`). **Without this, the guest
   agent has no communication path and `--source agent` will always fail.**
2. VM boots from the OS disk.
3. cloud-init detects the NoCloud ISO (`cidata` volume label).
4. cloud-init reads `user-data`, creates the user, configures SSH keys.
5. cloud-init installs `qemu-guest-agent` (via `packages:` directive).
6. cloud-init starts the guest agent (via `runcmd: systemctl enable --now qemu-guest-agent`).
7. The guest agent connects through the virtio-serial channel to the hypervisor.
8. DHCP assigns an IP to the guest's network interface.
9. `virsh domifaddr --source agent` returns the IP.

Steps 1-6 take time. The provisioner in `main.tf` polls every 10 seconds for
up to 60 attempts (10 minutes) to accommodate this.

### Why `wait_for_ip` was removed

The provider's `wait_for_ip = {}` attribute on network interfaces:
- Defaults to `source = "any"`, which tries both lease and ARP sources.
- Neither source works on bridged networks before the guest agent is running.
- Fails after 300 seconds with a timeout error.
- The `source = "agent"` option exists but hasn't been tested and may have
  the same issue (the agent isn't running yet during early boot).

We handle IP discovery ourselves in a `local-exec` provisioner instead.

---

## 8. Post-Provisioning with Ansible

### Two-phase model

This project uses a two-phase approach:

1. **Phase 1 — Infrastructure (OpenTofu):** Create volumes, build cloud-init
   ISO, define and start the domain, discover the VM's IP address, generate
   the Ansible inventory file (`inventory.ini`).

2. **Phase 2 — Configuration (Ansible):** Run `ansible-playbook` against the
   generated inventory to install development tools, configure the shell
   environment, deploy SSH keys, etc.

The phases are decoupled — OpenTofu generates `inventory.ini` and Ansible
consumes it. Ansible is run manually after `tofu apply` completes.

### ansible-core vs. the Ansible package

This project uses **ansible-core** (v2.20.3), not the full `ansible` community
package. The distinction:

| Package | Contents | Size |
|---|---|---|
| `ansible-core` | Core engine, `ansible-playbook`, `ansible-galaxy`, built-in modules (`ansible.builtin.*`) | ~2.4 MB wheel |
| `ansible` | ansible-core + ~85 community collections bundled | Much larger |

Since the project only uses `ansible.builtin` modules (ping, gather_facts,
zypper, file, copy), `ansible-core` alone is sufficient. Additional collections
can be installed via `ansible-galaxy` when needed — the project has
`ansible-galaxy/requirements.yml` for this purpose (currently listing
`community.general`).

### Python environment

ansible-core requires Python ≥ 3.10 (for v2.20.x). This project uses
**Python 3.13** (set in `.python-version`) managed by
[uv](https://github.com/astral-sh/uv). See [§9](#9-python-tooling-uv) for
uv details.

### Inventory generation

The inventory file is generated by the domain's `local-exec` provisioner
(not by a Terraform template). After discovering the VM's IP via
`virsh domifaddr --source agent`, the provisioner writes:

```ini
[dev_vm]
<IP> ansible_host=<IP> ansible_user=devenv ansible_ssh_private_key_file=".secret/id_rsa_jumphost"

[dev_vm:vars]
private_ssh_keys_to_upload=["key1","key2"]
```

### Running Ansible

```bash
uv run ansible-playbook -i inventory.ini playbook.yml
```

The `uv run` prefix ensures the playbook runs inside the project's virtual
environment with all dependencies available (see [§9](#9-python-tooling-uv)).

---

## 9. Python Tooling: uv

### What is uv?

[uv](https://docs.astral.sh/uv/) is an extremely fast Python package and project
manager written in Rust by [Astral](https://astral.sh/) (the team behind Ruff).
It is a single tool that replaces `pip`, `pip-tools`, `pipx`, `poetry`, `pyenv`,
and `virtualenv` — with 10–100× faster performance.

### Why uv?

- **Speed:** Dependency resolution and installation is near-instant compared to
  `pip` + `venv`.
- **Deterministic:** `uv.lock` (cross-platform lockfile) ensures reproducible
  installs.
- **Self-contained:** Manages Python versions, virtual environments, and packages
  without requiring a pre-installed Python.
- **Standards-based:** Uses standard `pyproject.toml` for project metadata — no
  proprietary config files.

### How it's used in this project

The project's `pyproject.toml` declares the single dependency:

```toml
[project]
name = "my-suse-machine"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = [
    "ansible-core>=2.20.3",
]
```

Key files:
- **`pyproject.toml`** — Project metadata and dependencies
- **`.python-version`** — Pins the Python version (3.13); uv will auto-download
  this version if not available on the system
- **`uv.lock`** — Lockfile with exact resolved versions of all transitive
  dependencies (ansible-core, Jinja2, PyYAML, cryptography, etc.)
- **`.venv/`** — Virtual environment, auto-created by `uv sync`

### Common commands

```bash
uv sync                    # Install dependencies from uv.lock into .venv/
uv run ansible-playbook    # Run a command inside the managed .venv
uv add <package>           # Add a dependency to pyproject.toml and re-lock
uv lock                    # Re-resolve dependencies and update uv.lock
uv python install 3.13     # Download and install Python 3.13 (if needed)
```

The `uv run` command automatically:
1. Creates `.venv/` if it doesn't exist
2. Installs/syncs dependencies if `uv.lock` has changed
3. Activates the environment
4. Runs the specified command

This means contributors don't need to manually `source .venv/bin/activate` —
`uv run <command>` handles everything.

### Version info

This project uses uv v0.10.8. The latest release is v0.10.11 (as of Mar 2026).
uv is under very active development with frequent releases.

---

## References

### Core project technologies
- [OpenTofu documentation](https://opentofu.org/docs/)
- [OpenTofu v1.11 — What's New](https://opentofu.org/docs/intro/whats-new/)
- [terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)
- [libvirt domain XML format](https://libvirt.org/formatdomain.html)

### First-boot provisioning
- [cloud-init documentation](https://cloudinit.readthedocs.io/)
- [cloud-init NoCloud datasource](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html)
- [Ignition specification](https://coreos.github.io/ignition/specs/)
- [Ignition supported platforms](https://coreos.github.io/ignition/supported-platforms/)
- [Combustion documentation (SLE Micro)](https://documentation.suse.com/sle-micro/)
- [Terraform Ignition provider](https://github.com/community-terraform-providers/terraform-provider-ignition)

### Image building
- [KIWI NG image build system](https://osinside.github.io/kiwi/)
- [KIWI NG — Image Profiles](https://osinside.github.io/kiwi/concept_and_workflow/profiles.html)
- [openSUSE Tumbleweed downloads](https://get.opensuse.org/tumbleweed/)
- [openSUSE MicroOS downloads](https://get.opensuse.org/microos/)

### Post-provisioning
- [ansible-core documentation](https://docs.ansible.com/ansible-core/devel/)
- [Ansible built-in modules](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/)

### Python tooling
- [uv documentation](https://docs.astral.sh/uv/)
- [uv — Working on Projects](https://docs.astral.sh/uv/guides/projects/)
- [uv GitHub repository](https://github.com/astral-sh/uv)
