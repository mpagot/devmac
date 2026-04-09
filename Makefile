TOFU       ?= tofu
UV         ?= uv
KVM_HOST   ?= root@qesap-kvm1.qe.prg3.suse.org
VM_NAME    ?= my-dev-vm
VERBOSITY  ?=

.PHONY: all validate format apply destroy list get-ip update-inventory galaxy-install provision lint clean-domain clean-state clean

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

get-ip:
	@ssh $(KVM_HOST) \
	  "virsh domifaddr '$(VM_NAME)' --source agent 2>/dev/null" \
	  | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1

update-inventory:
	@IP=$$(ssh $(KVM_HOST) \
	  "virsh domifaddr '$(VM_NAME)' --source agent 2>/dev/null" \
	  | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1) && \
	  [ -n "$$IP" ] || (echo "ERROR: could not get IP for $(VM_NAME)" >&2 && exit 1) && \
	  sed -i "s/[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/$$IP/g" inventory.ini && \
	  echo "inventory.ini updated: $$IP"

galaxy-install:
	$(UV) run ansible-galaxy collection install -r requirements.yml

provision: galaxy-install
	$(UV) run ansible-playbook -i inventory.ini playbook.yml $(VERBOSITY)

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
