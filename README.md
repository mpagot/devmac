# Development VM as Code

![logo](logo.png)

> For a dev machine that will survive!!!

Is a dotfile repo enough in the cloud age? This is my pretty openSUSE-centric way to set up a dev machine that I use every day
as QE dude in the fight.
This project uses OpenTofu and Ansible to define and provision a development VM on a remote (ssh accessible) KVM server.

## Supported features and tools I love

### Shell — Zsh

- [starship](https://starship.rs/) prompt — two-line, shows git status, language versions, command duration; username/hostname only in SSH sessions
- [atuin](https://atuin.sh/) — shell history search replacing Ctrl-R; fully local (no cloud sync), fuzzy search, secrets filter
- [zoxide](https://github.com/ajeetdsouza/zoxide) — smart `cd` (`z` / `zi`)
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder, wired into git aliases
- [eza](https://eza.rocks/) — modern `ls` replacement (`ll` alias)
- Some handy git aliases

And in case you do not like zsh, you also get bash, fish and nu.

### Terminal multiplexer — Tmux

[tmux](https://github.com/tmux/tmux) with [catppuccin Mocha](https://github.com/catppuccin/tmux) theme, sensible defaults, and custom splits (`|` / `_`) that preserve the working directory.
[zellij](https://zellij.dev/) also installed as an alternative.

### Editor — Helix

[Helix](https://helix-editor.com/) as the primary editor, configured with a full LSP suite:

| Language | LSP / Tool | Notes |
| -------- | ---------- | ----- |
| Python | `ruff`, `pylsp` | linting + completion |
| TOML | `taplo` | |
| Markdown | `markdown-oxide`, `marksman` | |
| Zig | `zls`, `codelldb` | debug adapter via vsix |
| Rust | `rust-analyzer` | via `rustup` |
| Bash | `bash-language-server` | via npm |
| YAML | `yaml-language-server` | via npm |
| Ansible | `@ansible/ansible-language-server` | via npm |
| Perl | `perlnavigator`, `vale-ls` | |
| HCL / Terraform | `terraform-ls` | |
| Multi-language | `prettier` | formatter, via npm |

### Git and GitHub — `git` + `gh` + `gh-dash`

Global config with sane defaults (`init.defaultBranch = main`, `core.editor = hx`).
Optional GPG commit signing: import your private key once.

- `gh` CLI authenticated headlessly via PAT, configured as git credential helper
- [gh-dash](https://github.com/dlvhdr/gh-dash) — terminal dashboard for PRs and issues
- [gh-grep](https://github.com/k1LoW/gh-grep) — grep across GitHub repos from the CLI

### Runtime version manager — asdf

[asdf](https://asdf-vm.com/) managing: nodejs and zig

### Code assistants

| Tool | Notes |
| ---- | ----- |
| [gemini-cli](https://github.com/google-gemini/gemini-cli) | Google Gemini agent for the terminal; auth type configurable (see below) |
| [opencode](https://opencode.ai/) | Terminal coding agent |
| [claude-code](https://claude.ai/) | Anthropic's Claude coding agent |
| [copilot](https://github.com/github/copilot-cli) | GitHub Copilot CLI |
| [pi](https://pi.ai/) | Inflection AI terminal agent |

All tools require an active subscription or API key. See the [Gemini CLI — authentication type](#gemini-cli--authentication-type) section for how to configure headless auth for gemini-cli.

### Other tools

[lazygit](https://github.com/jesseduffield/lazygit), [uv](https://docs.astral.sh/uv/), Python 3.11 / 3.12 / 3.14.

## Dependencies

Tools you need on the machine you use to create the remote VM.

- make
- [OpenTofu](https://opentofu.org/) >= 1.6
- Access to a remote KVM server
- [uv](https://docs.astral.sh/uv/) for managing Python/Ansible dependencies

**Clone the repository:**
```bash
git clone <repository-url>
cd <repository-name>
```

## Configuration

### KVM host and VM name

Create `.secret/make.env` with your KVM connection and desired hostname.
The Makefile uses these to generate `host.auto.tfvars` (auto-loaded by OpenTofu) and for all `virsh` commands.

```makefile
KVM_HOST = root@kvm-server.internal.example.com
VM_NAME  = my-dev-vm
```

### VM resources

Create a `terraform.tfvars` file for the remaining variables (see `variables.tf` for the full list with defaults).
You need at least your SSH public key:

```terraform
ssh_key                    = "ssh-rsa AAAA..." # Your public SSH key
ansible_private_key_path   = "~/.ssh/id_rsa"
private_ssh_keys_to_upload = ["~/.ssh/id_rsa"]
memory                     = 8192
vcpu                       = 4
disk_size                  = 53687091200 # 50GB
```

**Do not** put `hostname` or `libvirt_uri` here — they are generated automatically from `.secret/make.env`.

### Personal and org overrides

All personal or organization-specific data lives in the `.secret/` directory,
which is gitignored and never committed. The repository ships with generic
defaults that work out of the box; drop one or more of the files below into
`.secret/` to inject your real identity and infrastructure details.

| File                          | Purpose                                                        | Used by          |
| ----------------------------- | -------------------------------------------------------------- | ---------------- |
| `gh_pat`                      | GitHub Personal Access Token (plain text, mode 0600)           | Ansible          |
| `personal.yml`                | Ansible variable overrides (git name, email, signing key, etc.)| Ansible          |
| `gemini_env`                  | gemini-cli environment file deployed as `~/.gemini/.env`       | Ansible          |
| `gh_dash_config.yml`          | Full gh-dash config with your team-specific PR/issue sections  | Ansible          |
| `make.env`                    | KVM host and VM name — single source of truth for `hostname` and `libvirt_uri`  | Make / OpenTofu  |
| `gpg_private_key.asc`         | Exported GPG private key for signed commits (optional)         | Ansible          |

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

### GPG commit signing

To have every commit signed on the VM automatically, add the signing key ID
and enable signing in `.secret/personal.yml`:

```yaml
git_user_name: "Ada Lovelace"
git_user_email: "ada@example.com"
git_signing_key: "YOUR40CHARFINGERPRINT"
git_gpg_sign: "true"
```

Find your key ID with:

```bash
gpg --list-secret-keys --keyid-format=long
```

The output looks like:

```
sec  ed25519/44332211FFEEDDCCBBAA  2020-01-01 [SC]
     YOUR40CHARFINGERPRINT    ← use this full fingerprint
uid       [unknown] Your Name
ssb  cv25519/AABBCCDD11223344  2020-01-01 [E]    ← ignore (encryption subkey)
```

Use the 40-character fingerprint on the second line. The 16-character ID after
the `/` on the `sec` line also works, but the fingerprint is unambiguous and
preferred.

Then export your private key to `.secret/` on the Ansible controller **before**
running `make ansible-provision`:

```bash
gpg --export-secret-keys --armor YOURKEYID16HEX > .secret/gpg_private_key.asc
chmod 600 .secret/gpg_private_key.asc
```

Ansible will:
1. Import the key into `~/.gnupg/` on the VM (then delete the temp copy).
2. Set key trust to ultimate (non-interactively via `--import-ownertrust`).
3. Write `~/.gnupg/gpg-agent.conf` with `allow-loopback-pinentry` and an 8-hour
   passphrase cache so you only enter the passphrase once per SSH session.
4. Write `~/.gnupg/gpg.conf` with `pinentry-mode loopback`.
5. Set `user.signingkey` and `commit.gpgsign = true` in global git config.

> **Note**: your public key must also be uploaded to your GitHub account at
> <https://github.com/settings/gpg/new> for GitHub to show the "Verified" badge.
> Export it with `gpg --armor --export YOURKEYID16HEX`.

### Gemini CLI — authentication type

The `gemini_auth_type` variable (defined in `vars/gemini.yml`) controls the
`security.auth.selectedType` field written to `~/.gemini/settings.json` on the VM.

| Value | When to use |
| ----- | ----------- |
| `oauth-personal` | Interactive OAuth via Google Account — opens a browser on first run; **default** |
| `gemini-api-key` | API key from [Google AI Studio](https://aistudio.google.com/apikey); export `GEMINI_API_KEY` in the shell |
| `vertex-ai` | Vertex AI / Google Cloud; set `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION` |
| `compute-default-credentials` | Application Default Credentials (GCE, Cloud Shell, `gcloud auth application-default login`) |

The default (`oauth-personal`) is fine for interactive use. For headless or
service-account environments, override the value in `.secret/personal.yml`:

```yaml
gemini_auth_type: gemini-api-key
```

#### Environment variables — `.secret/gemini_env`

gemini-cli reads `~/.gemini/.env` at startup and injects its contents into the
process environment. This is the right place for credentials and project IDs that
must not be committed to the repository.

If `.secret/gemini_env` exists on the Ansible controller, Ansible will deploy it
as `~/.gemini/.env` (mode 0600) on the VM. If the file is absent the task is
skipped and no `.env` is created — gemini-cli starts without it.

Create the file on the controller:

```bash
cat > .secret/gemini_env << 'EOF'
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=us-central1
EOF
chmod 600 .secret/gemini_env
```

Or for API key auth:

```bash
cat > .secret/gemini_env << 'EOF'
GEMINI_API_KEY=your-api-key-here
EOF
chmod 600 .secret/gemini_env
```

Re-run with the `code_assist` tag to apply:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags code_assist
```

#### Extensions

gemini-cli supports [extensions](https://geminicli.com/docs/extensions/) —
add-ons that provide extra agent skills, MCP servers, and custom commands.
The playbook installs extensions listed in `gemini_extensions`
(`vars/gemini.yml`) on the VM non-interactively.

Default extensions:

| Extension | Source | What it adds |
| --------- | ------ | ------------ |
| `code-review` | [gemini-cli-extensions/code-review](https://github.com/gemini-cli-extensions/code-review) | `/code-review` and `/pr-code-review` commands |
| `conductor` | [gemini-cli-extensions/conductor](https://github.com/gemini-cli-extensions/conductor) | Orchestration agent for multi-step workflows |
| `gemini-cli-security` | [gemini-cli-extensions/security](https://github.com/gemini-cli-extensions/security) | Security scanning, vulnerability patching, PoC generation |

Extensions are installed only when their directory is missing from
`~/.gemini/extensions/` on the VM — re-runs are idempotent.

**Add an extension:** append an entry to `gemini_extensions` in
`vars/gemini.yml`. Use `ref` to pin a release tag (omit for the default
branch):

```yaml
gemini_extensions:
  - name: my-extension
    source: https://github.com/org/my-extension
    ref: v1.0.0
```

**Upgrade an extension:** bump the `ref` in `vars/gemini.yml`, remove the
extension directory on the VM, and re-run:

```bash
ssh devenv@<vm-ip> rm -rf ~/.gemini/extensions/conductor
uv run ansible-playbook -i inventory.ini playbook.yml --tags code_assist
```

### Variables

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

## Deployment

### Deploy the VM

```bash
make tofu-deploy
```

This runs `init → plan → apply`, discovers the VM's IP via the QEMU guest agent, and writes `inventory.ini`.

> **Note — expected error on first deploy:** The libvirt provider
> (v0.9.5–v0.9.7) has read-back bugs that cause `tofu apply` to fail
> with a consistency error on the *first* creation (`os.firmware` and
> `pty.path` fields). **The VM is created successfully** — the Makefile
> detects this, runs `tofu untaint`, and proceeds to generate inventory.
> Subsequent runs are idempotent and error-free.

### Provision with Ansible

After `make tofu-deploy`, an `inventory.ini` file will be automatically generated with the VM's IP address and SSH connection details.
An Ansible playbook `playbook.yml` is provided to install additional software.

```bash
make ansible-provision
```

To increase Ansible verbosity for troubleshooting, pass the `VERBOSITY` variable:

```bash
make ansible-provision VERBOSITY=-vvv
```

To run only a subset of tasks without reprovisioning the entire VM, use `--tags`:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags gh
uv run ansible-playbook -i inventory.ini playbook.yml --tags gpg
```

### Connect to the VM

After the VM is deployed, you can connect to it using SSH:

```bash
ssh <username>@<vm-ip-address>
```

The default username is `devenv`. The VM's IP address is in the generated `inventory.ini` file.

### Inventory generation

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

### Destroy and clean up

To destroy the VM and all associated resources, run:

```bash
make tofu-destroy
```

If `make tofu-deploy` fails after the domain has been defined on the KVM host (e.g. the
VM was defined but failed to start), the domain may be left orphaned on the host
while absent from the Terraform state. Subsequent applies will fail with
`domain 'xxx' already exists`. To recover, run:

```bash
make clean
```

This removes the domain from the KVM host (`virsh undefine --nvram`) and from
the local state. You can then re-run `make tofu-deploy`.

## Ricing Tweaking 'n Overclocking

The project is intentionally easy to extend. No roles, no Galaxy dependencies
for the core logic — everything is a list in a vars file or a block in
`playbook.yml`.

### Add system packages

Edit `vars/packages.yml`. Packages under `favorite_packages` are installed on
every provision; packages under `helix_zypper_packages` are grouped with the
Helix LSP dependencies and installed under the `helix` tag.

```yaml
favorite_packages:
  - your-new-package
```

Re-run with the `packages` tag to apply without full reprovisioning:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags packages
```

### Add a runtime version via asdf

Edit `vars/asdf_plugins.yml`. Each entry needs a plugin name, its upstream
repository URL, and one or more versions to install. Set `global: true` on the
version that should be the default.

```yaml
asdf_plugins:
  - name: python
    url: https://github.com/danhper/asdf-python.git
    versions:
      - version: "3.13.0"
        installed_version_pattern: "3\\.13\\.0"
        global: true
```

Re-run with the `asdf` tag:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags asdf
```

### Add shell aliases or functions

Edit `templates/zshrc.j2`. Aliases live in the aliases block around line 44;
shell functions follow. The file is a Jinja2 template so you can use
`{{ variable }}` expressions if needed.

```bash
alias k='kubectl'
```

Re-run with the `dotfiles` tag:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags dotfiles
```

### Tune shell history (atuin)

Edit `files/atuin_config.toml`. The most useful knobs:

| Key | Default | What it controls |
| --- | ------- | ---------------- |
| `filter_mode` | `"global"` | `"global"`, `"host"`, `"session"`, or `"directory"` |
| `search_mode` | `"fuzzy"` | `"fuzzy"` or `"fulltext"` |
| `inline_height` | `40` | lines of the inline search UI |
| `secrets_filter` | `true` | auto-hide tokens and keys from results |

Re-run with the `atuin` tag:

```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags atuin
```
