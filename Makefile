ANSIBLE_PLAYBOOK = ansible-playbook -i inventory.yaml

diff:
	$(ANSIBLE_PLAYBOOK) --check --diff playbook.yaml

push:
	$(ANSIBLE_PLAYBOOK) --diff playbook.yaml
