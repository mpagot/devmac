TOFU       ?= tofu
UV         ?= uv
KVM_HOST   ?= root@qesap-kvm1.qe.prg3.suse.org
VM_NAME    ?= my-dev-vm
VERBOSITY  ?=

.PHONY: \
	tofu-validate tofu-format tofu-apply tofu-destroy tofu-clean-state \
	virsh-list virsh-get-ip virsh-clean-domain \
	ansible-update-inventory ansible-galaxy-install ansible-provision ansible-lint \
	yaml-lint lint \
	clean

# ── Tofu / OpenTofu ────────────────────────────────────────────────────────

## tofu-validate: Validate Terraform configuration syntax and structure
tofu-validate:
	$(TOFU) validate

## tofu-format: Auto-format all Terraform files in-place (recursive)
tofu-format:
	$(TOFU) fmt -recursive

## tofu-apply: Provision infrastructure (non-interactive, auto-approve)
tofu-apply:
	$(TOFU) apply -auto-approve

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

## ansible-update-inventory: Refresh inventory.ini with the current IP of VM_NAME
ansible-update-inventory:
	@IP=$$(ssh $(KVM_HOST) \
	  "virsh domifaddr '$(VM_NAME)' --source agent 2>/dev/null" \
	  | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1) && \
	  [ -n "$$IP" ] || (echo "ERROR: could not get IP for $(VM_NAME)" >&2 && exit 1) && \
	  sed -i "s/[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/$$IP/g" inventory.ini && \
	  echo "inventory.ini updated: $$IP"

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
