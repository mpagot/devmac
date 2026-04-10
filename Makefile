TOFU       ?= tofu
UV         ?= uv
KVM_HOST   ?= root@your-kvm-host.example.com
VM_NAME    ?= my-dev-vm
VERBOSITY  ?=

# Optional personal/company overrides (gitignored).
# Example .secret/make.env:
#   KVM_HOST = root@kvm-server.internal.example.com
#   VM_NAME  = my-custom-vm
-include .secret/make.env

# Derived: libvirt connection URI built from KVM_HOST
LIBVIRT_URI = qemu+ssh://$(KVM_HOST)/system

.PHONY: \
	tofu-init tofu-validate tofu-format tofu-deploy tofu-destroy tofu-clean-state \
	virsh-list virsh-get-ip virsh-clean-domain \
	ansible-update-inventory ansible-galaxy-install ansible-provision ansible-lint \
	yaml-lint lint \
	clean

# ── Generated tfvars ───────────────────────────────────────────────────────
# host.auto.tfvars is auto-loaded by OpenTofu alongside terraform.tfvars.
# It provides hostname and libvirt_uri derived from the Makefile variables
# (KVM_HOST, VM_NAME) so there is a single source of truth.

host.auto.tfvars: $(wildcard .secret/make.env)
	@echo 'hostname    = "$(VM_NAME)"' > host.auto.tfvars
	@echo 'libvirt_uri = "$(LIBVIRT_URI)"' >> host.auto.tfvars

# ── Tofu / OpenTofu ────────────────────────────────────────────────────────

## tofu-init: Download providers and initialise the working directory
tofu-init: host.auto.tfvars
	$(TOFU) init

## tofu-validate: Validate Terraform configuration syntax and structure
tofu-validate:
	$(TOFU) validate

## tofu-format: Auto-format all Terraform files in-place (recursive)
tofu-format:
	$(TOFU) fmt -recursive

## tofu-deploy: Init, plan, then apply infrastructure (non-interactive)
##   The libvirt provider (v0.9.5–v0.9.7) has read-back bugs that always fail
##   the consistency check on *first* creation (os.firmware, pty.path).
##   The domain IS created successfully — we untaint it and generate inventory.
##   TODO: remove the untaint + inventory workaround once the provider is fixed.
tofu-deploy: tofu-init
	$(TOFU) plan
	$(TOFU) apply -auto-approve || { \
	  echo ""; \
	  echo ">>> apply failed — attempting provider read-back workaround..."; \
	  $(TOFU) state show libvirt_domain.domain >/dev/null 2>&1 || exit 1; \
	  $(TOFU) untaint libvirt_domain.domain || exit 1; \
	  echo ">>> Workaround applied successfully."; \
	}
	@# Generate inventory.ini (the local-exec provisioner may not have run)
	@$(MAKE) ansible-update-inventory

## tofu-destroy: Tear down all managed infrastructure (non-interactive)
tofu-destroy:
	$(TOFU) destroy -auto-approve

## tofu-clean-state: Remove the libvirt domain resource from local Tofu state
##   Use after virsh-clean-domain to resync state with reality
tofu-clean-state:
	$(TOFU) state rm libvirt_domain.domain 2>/dev/null || true

# ── Virsh / KVM host ───────────────────────────────────────────────────────

## virsh-list: List all VMs (running and stopped) on the KVM host
virsh-list:
	ssh $(KVM_HOST) "virsh list --all"

## virsh-get-ip: Print the guest IP address of VM_NAME (via qemu-guest-agent)
virsh-get-ip:
	@ssh $(KVM_HOST) \
	  "virsh domifaddr '$(VM_NAME)' --source agent 2>/dev/null" \
	  | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1

## virsh-clean-domain: Force-remove a stale VM from the KVM host
##   Use when Tofu cannot manage the domain (e.g. failed apply where define
##   succeeded but start failed)
virsh-clean-domain:
	ssh $(KVM_HOST) "virsh destroy '$(VM_NAME)' 2>/dev/null; virsh undefine '$(VM_NAME)' --nvram" || true

# ── Ansible ────────────────────────────────────────────────────────────────

## ansible-update-inventory: Discover VM IP and write inventory.ini
##   Reads connection details from tofu outputs (single source of truth).
##   Retries up to 60 times (10s apart) waiting for qemu-guest-agent.
ansible-update-inventory:
	@echo "Discovering IP for '$(VM_NAME)' via guest-agent..."
	@IP=""; \
	for i in $$(seq 1 60); do \
	  IP=$$(ssh $(KVM_HOST) \
	    "virsh domifaddr '$(VM_NAME)' --source agent 2>/dev/null" \
	    | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1); \
	  [ -n "$$IP" ] && break; \
	  echo "  Attempt $$i/60: no IP yet, waiting 10s..."; \
	  sleep 10; \
	done; \
	[ -n "$$IP" ] || { echo "ERROR: could not get IP for $(VM_NAME) after 10 min" >&2; exit 1; }; \
	A_USER=$$($(TOFU) output -raw ansible_user) && \
	A_KEY=$$($(TOFU) output -raw ansible_private_key_path) && \
	A_KEYS=$$($(TOFU) output -json private_ssh_keys_to_upload) && \
	{ echo "[dev_vm]"; \
	  echo "$$IP ansible_host=$$IP ansible_user=$$A_USER ansible_ssh_private_key_file=\"$$A_KEY\""; \
	  echo ""; \
	  echo "[dev_vm:vars]"; \
	  echo "ansible_python_interpreter=/usr/bin/python3"; \
	  echo "private_ssh_keys_to_upload=$$A_KEYS"; \
	} > inventory.ini; \
	echo "inventory.ini written: $$IP"

## ansible-galaxy-install: Install required Ansible collections from requirements.yml
ansible-galaxy-install:
	$(UV) run ansible-galaxy collection install -r requirements.yml

## ansible-provision: Run the full configuration playbook against inventory.ini
ansible-provision: ansible-galaxy-install
	$(UV) run ansible-playbook -i inventory.ini playbook.yml $(VERBOSITY)

## ansible-lint: Lint the Ansible playbook with ansible-lint
ansible-lint:
	$(UV) run ansible-lint playbook.yml

# ── Linting ────────────────────────────────────────────────────────────────

## yaml-lint: Lint all YAML files (playbook, vars/, requirements, files/)
yaml-lint:
	$(UV) run yamllint playbook.yml requirements.yml vars/ files/

## lint: Run all checks — format Terraform, validate, lint Ansible and YAML
lint: tofu-format tofu-validate ansible-lint yaml-lint

# ── Cleanup ────────────────────────────────────────────────────────────────

## clean: Full cleanup — remove stale domain from KVM host and resync Tofu state
clean: virsh-clean-domain tofu-clean-state
