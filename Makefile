.PHONY: ansible-deps install install-full install-full-force run-graphical

ansible-deps:
	ansible-galaxy collection install -r requirements.yml

install:
	./scripts/qemu-install.sh

install-full: ansible-deps
	./scripts/qemu-install.sh --post-install

install-full-force: ansible-deps
	./scripts/qemu-install.sh --post-install --force

run-graphical:
	./scripts/qemu-graphical.sh
