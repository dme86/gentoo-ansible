.PHONY: ansible-deps install post-install run-graphical

ansible-deps:
	ansible-galaxy collection install -r requirements.yml

install: ansible-deps
	./scripts/qemu-install.sh --post-install $(ARGS)

run-graphical:
	./scripts/qemu-graphical.sh

post-install: ansible-deps
	ansible-playbook -i .qemu/inventory.ini post_install.yml -e post_install_target=gentoo_installed
