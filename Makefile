TOFU       ?= tofu
UV         ?= uv
KVM_HOST   ?= root@qesap-kvm1.qe.prg3.suse.org
VM_NAME    ?= my-dev-vm

.PHONY: all validate format apply destroy list galaxy-install provision lint clean-domain clean-state clean

all: format validate

validate:
	$(TOFU) validate

format:
	$(TOFU) fmt -recursive

apply:
	$(TOFU) apply -auto-approve

destroy:
	$(TOFU) destroy -auto-approve

list:
	ssh $(KVM_HOST) "virsh list --all"

galaxy-install:
	$(UV) run ansible-galaxy collection install -r requirements.yml

provision: galaxy-install
	$(UV) run ansible-playbook -i inventory.ini playbook.yml

lint:
	$(UV) run ansible-lint playbook.yml

# Remove a stale domain from the KVM host that tofu can't manage
# (e.g. after a failed apply where define succeeded but start failed)
clean-domain:
	ssh $(KVM_HOST) "virsh destroy '$(VM_NAME)' 2>/dev/null; virsh undefine '$(VM_NAME)' --nvram" || true

# Remove the domain resource from local tofu state (use after clean-domain)
clean-state:
	$(TOFU) state rm libvirt_domain.domain 2>/dev/null || true

# Full cleanup: remove stale domain from host + state
clean: clean-domain clean-state
