ANSIBLE_PLAYBOOK = ansible-playbook -i inventory.yaml

all: submodules-generated

keepalived:
	$(MAKE) -C os/etc/keepalived all
keepalived-clean:
	$(MAKE) -C os/etc/keepalived clean
nomad:
	$(MAKE) -C os/etc/nomad.d all
nomad-clean:
	$(MAKE) -C os/etc/nomad.d clean

submodules-generated: keepalived
submodules-clean: keepalived-clean

diff: submodules-generated
	$(ANSIBLE_PLAYBOOK) --check --diff playbook.yaml

push: submodules-generated
	$(ANSIBLE_PLAYBOOK) --diff playbook.yaml

clean: submodules-clean
