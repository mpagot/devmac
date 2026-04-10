# AGENTS.md

## What this repo is

OpenTofu + Ansible project that provisions an openSUSE Tumbleweed dev VM on a remote KVM/libvirt host.
No application code — the "product" is infrastructure config and dotfiles.

## Prerequisites

- `uv` (manages Python, Ansible, linters via `pyproject.toml`)
- `tofu` (OpenTofu — not `terraform`)
- SSH access to the KVM host defined in `.secret/make.env`

Bootstrap: `uv sync && uv run ansible-galaxy collection install -r requirements.yml`

## Key commands

```bash
make lint                  # all checks: tofu fmt + validate + ansible-lint + yamllint
make tofu-deploy           # init → plan → apply (safe to re-run after editing .tf files)
make ansible-provision     # run Ansible playbook (installs galaxy collections first)
make clean                 # recover from stuck domain: virsh undefine + state rm
```

`make lint` is the right pre-commit check. Order inside it: `tofu-format → tofu-validate → ansible-lint → yaml-lint`.

## Secrets and personal data — `.secret/` override pattern

**Never commit personal names, emails, company hostnames, or tokens.** All tracked files use generic defaults. Real values live in `.secret/` (gitignored):

| File | Purpose | Consumer |
|---|---|---|
| `gh_pat` | GitHub PAT (required) | Ansible `lookup('file')` |
| `personal.yml` | Ansible var overrides (`git_user_name`, `git_user_email`, `gh_username`) | `playbook.yml` pre_tasks `include_vars` |
| `gh_dash_config.yml` | Full gh-dash config with team-specific filters | `playbook.yml` conditional `copy` |
| `make.env` | `KVM_HOST` and `VM_NAME` — single source of truth for hostname and libvirt_uri | Makefile → `host.auto.tfvars` |


## File layout that matters

- `main.tf` / `variables.tf` / `output.tf` — OpenTofu infra (libvirt provider, cloud-init ISO build, domain)
- `playbook.yml` — single Ansible playbook, all tasks inline (no roles)
- `vars/` — Ansible variable files loaded by `vars_files` + optional `.secret/personal.yml`
- `files/` — static config files deployed via `copy`
- `templates/` — Jinja2 templates deployed via `template` (`gh_config.yml.j2`, `zshrc.j2`)
- `docs/TECH_STACK.md` — deep rationale docs; consult when changing infra or provider behavior

## Gotchas

- **`tofu` not `terraform`**: the binary is `tofu`, not `terraform`. The Makefile variable is `$(TOFU)`.
- **`uv run` prefix**: Ansible and linters are not globally installed. Always run them through `uv run` (or `make`, which does this).
- **`inventory.ini` is generated**: created by `make ansible-update-inventory` (called by `tofu-deploy`), not checked in. Don't create it manually.
- **`host.auto.tfvars` is generated**: created by the Makefile from `KVM_HOST` and `VM_NAME`. Don't edit it directly — change `.secret/make.env` instead.
- **No Terraform remote state**: state is local (`terraform.tfstate`, gitignored). There is no locking or shared backend.
- **Playbook tag convention**: most task blocks have tags (`packages`, `helix`, `gh`, `dotfiles`, `atuin`, `asdf`, `tmux`, `ssh_keys`). Run subsets with `--tags`.
