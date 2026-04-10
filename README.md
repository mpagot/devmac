# Development VM as Code

Is a dotfile repo enough in the cloud age? This is my pretty openSUSE centric way to setup a dev machine that I use everyday
as QE dude in the fight.
This project uses OpenTofu and Ansible to define and provision a development VM on a remote (ssh accessible) KVM server.

## Requirements

- [OpenTofu](https://opentofu.org/) >= 1.6
- Access to a remote KVM server
- [uv](https://docs.astral.sh/uv/) for managing Python/Ansible dependencies


## Usage

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd <repository-name>
    ```

2.  **Set the KVM host and VM name:**
    Create `.secret/make.env` with your KVM connection and desired hostname.
    The Makefile uses these to generate `host.auto.tfvars` (auto-loaded by
    OpenTofu) and for all `virsh` commands.
    ```makefile
    KVM_HOST = root@kvm-server.internal.example.com
    VM_NAME  = my-dev-vm
    ```

3.  **Configure the VM:**
    Create a `terraform.tfvars` file for the remaining variables (see
    `variables.tf` for the full list with defaults).  You need at least
    your SSH public key:
    ```terraform
    ssh_key                    = "ssh-rsa AAAA..." # Your public SSH key
    ansible_private_key_path   = "~/.ssh/id_rsa"
    private_ssh_keys_to_upload = ["~/.ssh/id_rsa"]
    memory                     = 8192
    vcpu                       = 4
    disk_size                  = 53687091200 # 50GB
    ```
    **Do not** put `hostname` or `libvirt_uri` here — they are generated
    automatically from `.secret/make.env`.

4.  **Deploy the VM:**
    ```bash
    make tofu-deploy
    ```
    This runs `init → plan → apply`, discovers the VM's IP via the QEMU
    guest agent, and writes `inventory.ini`.

    > **Note — expected error on first deploy:** The libvirt provider
    > (v0.9.5–v0.9.7) has read-back bugs that cause `tofu apply` to fail
    > with a consistency error on the *first* creation (`os.firmware` and
    > `pty.path` fields). **The VM is created successfully** — the Makefile
    > detects this, runs `tofu untaint`, and proceeds to generate inventory.
    > Subsequent runs are idempotent and error-free.

5.  **Connect to the VM:**
    After the VM is deployed, you can connect to it using SSH:
    ```bash
    ssh <username>@<vm-ip-address>
    ```
    The default username is `devenv`. The VM's IP address is in the
    generated `inventory.ini` file.

6.  **Provision with Ansible:**
    -   After `make tofu-deploy`, an `inventory.ini` file will be automatically generated with the VM's IP address and SSH connection details.
    -   An Ansible playbook `playbook.yml` is provided to install additional software.
    -   Run the playbook:
        ```bash
        make ansible-provision
        ```
        To increase Ansible verbosity for troubleshooting, pass the `VERBOSITY` variable:
        ```bash
        make ansible-provision VERBOSITY=-vvv
        ```

### GitHub PAT for `gh` CLI authentication

The playbook configures `gh` (GitHub CLI) on the VM so the user can start using
it immediately over SSH without any manual login. This requires a GitHub Personal
Access Token (PAT) stored on the Ansible controller before provisioning.

**Step 1 — Create the PAT on GitHub:**

1. Go to <https://github.com/settings/tokens> → **Generate new token (classic)**
2. Set a note (e.g. `dev-vm-gh-cli`) and an expiration date
3. Select at minimum these scopes: `repo`, `read:org`, `gist`
4. Click **Generate token** and copy the value (shown only once)

**Step 2 — Store it in the project:**

```bash
echo "ghp_yourTokenHere" > .secret/gh_pat
chmod 600 .secret/gh_pat
```

The `.secret/` directory is already gitignored. The file must be present before
running `ansible-playbook` or `make ansible-provision`. The token is read by Ansible
via `vars/gh.yml` using `lookup('file', '.secret/gh_pat')` and is never written
to Ansible logs (`no_log: true`).

To run only the gh-related tasks without reprovisioning the entire VM:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags gh
```

### Personal and company overrides

All personal or organisation-specific data lives in the `.secret/` directory,
which is gitignored and never committed. The repository ships with generic
defaults that work out of the box; drop one or more of the files below into
`.secret/` to inject your real identity and infrastructure details.

| File                          | Purpose                                                        | Used by          |
| ----------------------------- | -------------------------------------------------------------- | ---------------- |
| `gh_pat`                      | GitHub Personal Access Token (plain text, mode 0600)           | Ansible          |
| `personal.yml`                | Ansible variable overrides (git name, email, etc.)             | Ansible          |
| `gh_dash_config.yml`          | Full gh-dash config with your team-specific PR/issue sections  | Ansible          |
| `make.env`                    | KVM host and VM name — single source of truth for `hostname` and `libvirt_uri`  | Make / OpenTofu  |

`make.env` is the most important: the Makefile generates `host.auto.tfvars`
from `KVM_HOST` and `VM_NAME`, which OpenTofu auto-loads alongside
`terraform.tfvars`.  This avoids duplicating hostname and connection details
across Make and Terraform configs.

`terraform.tfvars` (also gitignored) holds the remaining infrastructure
variables such as `ssh_key`, `memory`, `vcpu`, and `disk_size`.

**Example `.secret/personal.yml`:**

```yaml
git_user_name: "Ada Lovelace"
git_user_email: "ada@example.com"
```

**Example `.secret/make.env`:**

```makefile
KVM_HOST = root@kvm-server.internal.example.com
VM_NAME  = ada-dev-vm
```

6.  **Destroy the VM:**
    To destroy the VM and all associated resources, run:
    ```bash
    make tofu-destroy
    ```

7.  **Clean up a stale domain:**
    If `make tofu-deploy` fails after the domain has been defined on the KVM host (e.g. the
    VM was defined but failed to start), the domain may be left orphaned on the host
    while absent from the Terraform state. Subsequent applies will fail with
    `domain 'xxx' already exists`. To recover, run:
    ```bash
    make clean
    ```
    This removes the domain from the KVM host (`virsh undefine --nvram`) and from
    the local state. You can then re-run `make tofu-deploy`.

## Variables

Infrastructure variables are split across two gitignored files to avoid
duplication between Make and OpenTofu:

```
.secret/make.env              terraform.tfvars
  KVM_HOST, VM_NAME             ssh_key, memory, vcpu, ...
        |                              |
        v                              |
  Makefile generates                   |
  host.auto.tfvars                     |
    hostname, libvirt_uri              |
        |                              |
        +-------------+----------------+
                      v
               OpenTofu (auto-loads both)
                      |
                      v
               tofu output
                      |
                      v
               inventory.ini
```

- **`.secret/make.env`** — `KVM_HOST` and `VM_NAME` (the Makefile generates `host.auto.tfvars` with `hostname` and `libvirt_uri`)
- **`terraform.tfvars`** — everything else listed below

| Variable                     | Description                                            | Default                                                              |
| ---------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------- |
| `hostname`                   | Hostname for the VM (**set via `VM_NAME` in make.env**)| `"opensuse-dev-vm"`                                                  |
| `libvirt_uri`                | URI for the libvirt connection (**set via `KVM_HOST`**) | `""` (generated from `KVM_HOST`)                                     |
| `username`                   | Username to be created in the VM                       | `"devenv"`                                                           |
| `ssh_key`                    | SSH key for the user                                   | `""`                                                                 |
| `ansible_private_key_path`   | Path to the SSH private key for Ansible                | `"~/.ssh/id_rsa"`                                                    |
| `private_ssh_keys_to_upload` | A list of local paths to private SSH keys to upload    | `[]`                                                                 |
| `libvirt_pool`               | Libvirt storage pool to use                            | `"default"`                                                          |
| `uefi_loader_path`           | Path to the UEFI loader binary for the VM              | `"/usr/share/qemu/ovmf-x86_64-code.bin"`                             |
| `uefi_nvram_template_path`   | Path to the UEFI NVRAM template file for the VM        | `"/usr/share/qemu/ovmf-x86_64-vars.bin"`                           |
| `disk_size`                  | Disk size for the VM in bytes                          | `21474836480` (20GB)                                                 |
| `memory`                     | Memory for the VM in MB                                | `4096`                                                               |
| `vcpu`                       | Number of vCPUs for the VM                             | `2`                                                                  |
| `network_bridge`             | Name of the bridge to connect the VM to                | `"br0"`                                                              |

## Note on Inventory Generation

The `inventory.ini` file is generated by `make ansible-update-inventory`
(called automatically at the end of `make tofu-deploy`). It discovers the
VM's IP via the QEMU guest agent and reads connection details from OpenTofu
outputs.

The IP discovery retries for up to 10 minutes, which covers the time needed
for cloud-init to run and `qemu-guest-agent` to start.

To refresh the IP without redeploying (e.g. after a DHCP lease change):

```bash
make ansible-update-inventory
```
