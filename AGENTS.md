# AGENTS.md — Development Machine as Code

OpenTofu + Ansible project that provisions an openSUSE Tumbleweed dev VM on a remote KVM/libvirt host.
No application code — the product is infrastructure config and dotfiles.

## Prerequisites

- `uv` (manages Python, Ansible, linters via `pyproject.toml`)
- `tofu` (OpenTofu)
- SSH access to the KVM host defined in `.secret/make.env`

Bootstrap: `uv sync && uv run ansible-galaxy collection install -r requirements.yml`

## Key Commands

```bash
make lint                  # tofu-format → tofu-validate → ansible-lint → yaml-lint
make tofu-deploy           # init → plan → apply, then generate inventory.ini
make ansible-provision     # install galaxy collections, run playbook
make clean                 # virsh undefine + tofu state rm (recover stuck domains)
```

`make lint` is the pre-commit check. Run subsets of the playbook with `--tags`:
```bash
uv run ansible-playbook -i inventory.ini playbook.yml --tags gh,dotfiles
```

Available tags: `always`, `asdf`, `atuin`, `dotfiles`, `gh`, `gpg`, `helix`, `packages`, `shell`, `ssh_keys`, `tmux`, `update`.

## File Layout

| Path | Purpose |
|---|---|
| `main.tf` / `variables.tf` / `output.tf` | OpenTofu infra (libvirt provider, cloud-init ISO, domain) |
| `playbook.yml` | Single Ansible playbook, all tasks inline (no roles) |
| `vars/` | Ansible variable files (`packages.yml`, `gh.yml`, `asdf_plugins.yml`, `helix_github_binaries.yml`) |
| `files/` | Static configs deployed via `copy` (atuin, helix, starship, tmux, gh-dash) |
| `templates/` | Jinja2 templates deployed via `template` (`zshrc.j2`, `gh_config.yml.j2`) |
| `docs/TECH_STACK.md` | Deep rationale on infra, provider behaviour, and tooling decisions |

## Secrets — `.secret/` Override Pattern

**Never commit personal names, emails, hostnames, or tokens.** All tracked files use generic defaults. Real values live in `.secret/` (gitignored):

| File | Purpose | Consumer |
|---|---|---|
| `make.env` | `KVM_HOST` and `VM_NAME` — single source of truth | Makefile → `host.auto.tfvars` |
| `personal.yml` | Ansible var overrides (git name, email, signing key) | `playbook.yml` `include_vars` |
| `gh_pat` | GitHub PAT for headless `gh` auth | Ansible `lookup('file')` |
| `gh_dash_config.yml` | Full gh-dash config with team-specific filters | `playbook.yml` conditional `copy` |
| `gpg_private_key.asc` | GPG private key for signed commits (optional) | `playbook.yml` GPG block (tag `gpg`) |

`terraform.tfvars` (also gitignored) holds remaining infra vars: `ssh_key`, `memory`, `vcpu`, `disk_size`. See `variables.tf` for the full list.

## Critical Constraints

- **Binary is `tofu`:** The Makefile variable is `$(TOFU)`. No OpenTofu-specific features are used; `terraform` would also work, but all scripts expect `tofu`.
- **`uv run` prefix:** Ansible and linters are not globally installed. Always use `uv run` (or `make`, which does this).
- **`inventory.ini` is generated:** Created by `make ansible-update-inventory` (called by `tofu-deploy`). Do not create or edit manually.
- **`host.auto.tfvars` is generated:** Created by the Makefile from `KVM_HOST`/`VM_NAME`. Change `.secret/make.env` instead.
- **Local state only:** `terraform.tfstate` is gitignored. No remote backend, no locking.
- **Consult `docs/TECH_STACK.md`** before changing infra, provider config, or cloud-init behaviour.
