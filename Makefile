ANSIBLE_PLAYBOOK = ansible-playbook -i inventory.yaml

keepalived:
	$(MAKE) -C os/etc/keepalived all
keepalived-clean:
	$(MAKE) -C os/etc/keepalived clean
submodules-generated: keepalived
submodules-clean: keepalived-clean

diff: submodules-generated
	$(ANSIBLE_PLAYBOOK) --check --diff playbook.yaml

push: submodules-generated
	$(ANSIBLE_PLAYBOOK) --diff playbook.yaml

default: diff

clean: submodules-clean
