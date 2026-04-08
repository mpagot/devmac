provider "libvirt" {
  uri = var.libvirt_uri
}

# --- Cloud-init configuration ---
# The openSUSE Tumbleweed Cloud image uses cloud-init for first-boot provisioning.
# We build a NoCloud ISO (volume label "cidata") containing user-data and meta-data,
# then attach it as a CDROM to the domain.

locals {
  # Extract "root@host" from URI like "qemu+ssh://root@host/system"
  kvm_ssh_host = regex("//([^/]+)/", var.libvirt_uri)[0]

  cloudinit_dir             = "${path.module}/.cloudinit"
  cloudinit_iso_local_path  = "${path.module}/.cloudinit.iso"
  cloudinit_iso_remote_path = "/var/lib/libvirt/images/${var.hostname}-cidata.iso"

  cloud_init_user_data = <<-YAML
    #cloud-config
    users:
      - name: ${var.username}
        groups: wheel
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        lock_passwd: true
        ssh_authorized_keys:
          - ${var.ssh_key}
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
  YAML

  cloud_init_meta_data = <<-YAML
    instance-id: ${var.hostname}
    local-hostname: ${var.hostname}
  YAML
}

# Write cloud-init files to local .cloudinit/ directory
resource "local_file" "cloud_init_user_data" {
  content  = local.cloud_init_user_data
  filename = "${local.cloudinit_dir}/user-data"
}

resource "local_file" "cloud_init_meta_data" {
  content  = local.cloud_init_meta_data
  filename = "${local.cloudinit_dir}/meta-data"
}

# Build the NoCloud ISO and upload it to the KVM host.
# mkisofs creates an ISO with the "cidata" volume label that cloud-init recognizes
# as a NoCloud datasource.
resource "terraform_data" "cloudinit_iso" {
  depends_on = [
    local_file.cloud_init_user_data,
    local_file.cloud_init_meta_data,
  ]

  triggers_replace = {
    user_data = local_file.cloud_init_user_data.content_md5
    meta_data = local_file.cloud_init_meta_data.content_md5
  }

  input = {
    ssh_host    = local.kvm_ssh_host
    remote_path = local.cloudinit_iso_remote_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkisofs -output '${local.cloudinit_iso_local_path}' \
        -volid cidata \
        -joliet -rock \
        '${local.cloudinit_dir}/user-data' \
        '${local.cloudinit_dir}/meta-data'
      scp '${local.cloudinit_iso_local_path}' '${local.kvm_ssh_host}:${local.cloudinit_iso_remote_path}'
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh '${self.input.ssh_host}' 'rm -f \"${self.input.remote_path}\"' || true"
  }
}

# --- Volumes ---

resource "libvirt_volume" "os_image" {
  name = "${var.hostname}-os_image.qcow2"
  pool = var.libvirt_pool
  target = {
    format = { type = "qcow2" }
  }
  create = {
    content = {
      url = var.os_image_url
    }
  }
}

resource "libvirt_volume" "disk" {
  name = "${var.hostname}.qcow2"
  pool = var.libvirt_pool
  target = {
    format = { type = "qcow2" }
  }
  capacity = var.disk_size
  backing_store = {
    path   = libvirt_volume.os_image.path
    format = { type = "qcow2" }
  }
}

# --- Domain ---

resource "libvirt_domain" "domain" {
  name        = var.hostname
  memory      = var.memory
  memory_unit = "MiB"
  vcpu        = var.vcpu
  type        = "kvm"
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
    boot_devices = [{ dev = "hd" }]
  }

  features = {
    acpi = true
  }

  cpu = {
    mode = "host-passthrough"
  }

  depends_on = [terraform_data.cloudinit_iso]

  devices = {
    disks = [
      # Main OS disk (qcow2 overlay backed by os_image)
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = var.libvirt_pool
            volume = libvirt_volume.disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      # Cloud-init NoCloud ISO (CDROM)
      {
        device = "cdrom"
        driver = {
          name = "qemu"
          type = "raw"
        }
        source = {
          file = {
            file = local.cloudinit_iso_remote_path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      },
    ]
    interfaces = [
      {
        source = {
          bridge = {
            bridge = var.network_bridge
          }
        }
        model = {
          type = "virtio"
        }
        # NOTE: wait_for_ip is intentionally omitted — it's broken on bridged
        # networks without qemu-guest-agent (see PROVIDER_ISSUES.md).
        # IP discovery is handled by the provisioner below using virsh domifaddr.
      }
    ]
    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
        source = {
          pty = { path = "" }
        }
      }
    ]
    # Virtio-serial channel required for QEMU guest agent communication.
    # Without this, `virsh domifaddr --source agent` cannot work.
    channels = [
      {
        source = {
          unix = {}
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      # Wait for the VM to boot, run cloud-init, start qemu-guest-agent,
      # and acquire a DHCP lease.
      echo "Waiting for VM '${self.name}' to get an IP address (via guest agent)..."
      IP=""
      for i in $(seq 1 60); do
        IP=$(ssh "${local.kvm_ssh_host}" \
          "virsh domifaddr '${self.name}' --source agent 2>/dev/null" \
          | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1) || true
        if [ -n "$IP" ]; then
          break
        fi
        echo "  Attempt $i/60: no IP yet, waiting 10s..."
        sleep 10
      done

      if [ -z "$IP" ]; then
        echo "ERROR: Could not determine IP address for VM '${self.name}' after 10 minutes"
        exit 1
      fi

      echo "VM IP address: $IP"

      {
        echo "[dev-vm]"
        echo "$IP ansible_host=$IP ansible_user=${var.username} ansible_ssh_private_key_file=\"${var.ansible_private_key_path}\""
        echo ""
        echo "[dev-vm:vars]"
        echo "private_ssh_keys_to_upload=${jsonencode(var.private_ssh_keys_to_upload)}"
      } > inventory.ini
    EOT
  }
}

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
  required_version = ">= 0.13"
}
