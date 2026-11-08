.PHONY: ansible-deps install run-graphical

ansible-deps:
	ansible-galaxy collection install -r requirements.yml

install: ansible-deps
	./scripts/qemu-install.sh --post-install $(ARGS)

run-graphical:
	./scripts/qemu-graphical.sh
