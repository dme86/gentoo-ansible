.PHONY: ansible-deps install install-full run-graphical

ansible-deps:
	ansible-galaxy collection install -r requirements.yml

install:
	./scripts/qemu-install.sh

install-full: ansible-deps
	./scripts/qemu-install.sh --post-install

run-graphical:
	./scripts/qemu-graphical.sh
