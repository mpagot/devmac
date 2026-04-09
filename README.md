# Development VM as Code

This project uses OpenTofu and Ansible to define and provision a development VM on a remote KVM server. It uses cloud-init (NoCloud datasource) for first-boot configuration.

## Requirements

- [OpenTofu](https://opentofu.org/) >= 1.6
- Access to a remote KVM server
- [uv](https://docs.astral.sh/uv/) for managing Python/Ansible dependencies

## Local Development Environment Setup

This project uses `uv` to manage Python and Ansible dependencies via `pyproject.toml`.

1.  **Install `uv`:**
    If you don't have `uv` installed, you can install it via pip or pipx:
    ```bash
    # using pipx
    pipx install uv

    # using pip
    pip install uv
    ```

2.  **Install dependencies and activate the virtual environment:**
    ```bash
    uv sync
    source .venv/bin/activate
    ```

3.  **Install Ansible Galaxy collections:**
    ```bash
    uv run ansible-galaxy collection install -r requirements.yml
    ```

## Usage

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd <repository-name>
    ```

2.  **Configure the VM:**
    -   Create a `terraform.tfvars` file to override the default variables defined in `variables.tf`.
        - You will need to at least provide your ssh public key in the `ssh_key` variable.
    -   Example `terraform.tfvars`:
        ```terraform
        hostname                   = "my-dev-vm"
        ssh_key                    = "ssh-rsa AAAA..." # Your public SSH key
        ansible_private_key_path   = "~/.ssh/id_rsa"    # Path to your private SSH key
        private_ssh_keys_to_upload = ["~/.ssh/id_rsa_other_server", "~/.ssh/id_rsa_another_server"]
        libvirt_uri                = "qemu+ssh://root@qesap-kvm1.qe.prg3.suse.org/system"
        memory                     = 8192
        vcpu                       = 4
        disk_size                  = 53687091200 # 50GB
        ```

3.  **Initialize OpenTofu:**
    ```bash
    tofu init
    ```

4.  **Deploy the VM:**
    ```bash
    tofu apply
    ```
    Confirm the deployment by typing `yes` when prompted.

5.  **Connect to the VM:**
    After the VM is deployed, you can connect to it using SSH:
    ```bash
    ssh <username>@<vm-ip-address>
    ```
    The default username is `devenv`. The VM's IP address will be displayed in the `tofu apply` output, and also written to the generated `inventory.ini` file.

6.  **Provision with Ansible:**
    -   After `tofu apply`, an `inventory.ini` file will be automatically generated with the VM's IP address and SSH connection details.
    -   An Ansible playbook `playbook.yml` is provided to install additional software.
    -   Run the playbook:
        ```bash
        uv run ansible-playbook -i inventory.ini playbook.yml
        ```
        Or use the Makefile target:
        ```bash
        make provision
        ```
        To increase Ansible verbosity for troubleshooting, pass the `VERBOSITY` variable:
        ```bash
        make provision VERBOSITY=-vvv
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
running `ansible-playbook` or `make provision`. The token is read by Ansible
via `vars/gh.yml` using `lookup('file', '.secret/gh_pat')` and is never written
to Ansible logs (`no_log: true`).

To run only the gh-related tasks without reprovisioning the entire VM:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags gh
```

7.  **Destroy the VM:**
    To destroy the VM and all associated resources, run:
    ```bash
    tofu destroy
    ```
    Confirm the destruction by typing `yes` when prompted.

8.  **Clean up a stale domain:**
    If `tofu apply` fails after the domain has been defined on the KVM host (e.g. the
    VM was defined but failed to start), the domain may be left orphaned on the host
    while absent from the Terraform state. Subsequent applies will fail with
    `domain 'xxx' already exists`. To recover, run:
    ```bash
    make clean
    ```
    This removes the domain from the KVM host (`virsh undefine --nvram`) and from
    the local state. You can then re-run `tofu apply`.

## Variables

The following variables can be configured in your `terraform.tfvars` file:

| Variable                     | Description                                            | Default                                                              |
| ---------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------- |
| `libvirt_uri`                | URI for the libvirt connection                         | `"qemu+ssh://root@qesap-kvm1.qe.prg3.suse.org/system"`             |
| `hostname`                   | Hostname for the VM                                    | `"opensuse-dev-vm"`                                                  |
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

The `inventory.ini` file is automatically generated by a `local-exec` provisioner when the VM is created. It queries the VM's IP address from the KVM host using `virsh domifaddr`.

The provisioner only runs when the domain resource is **created** (not on every `tofu apply`). This means:

- If the VM is destroyed and recreated, the inventory is regenerated automatically.
- If you need to refresh the IP without recreating the VM (e.g. after a DHCP lease change), you can force recreation with:
  ```bash
  tofu apply -replace=libvirt_domain.domain
  ```
  Or query the IP manually:
  ```bash
  ssh root@<kvm-host> "virsh domifaddr <vm-name> --source arp"
  ```
