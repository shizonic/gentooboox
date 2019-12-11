SUDO := sudo

format:
	shfmt -l -w linbox.sh lib/flavors/*/*.sh

check:
	shellcheck --exclude=SC1090,SC2039 linbox.sh lib/flavors/*/*.sh

lint:
	shfmt -d linbox.sh lib/flavors/*/*.sh

qemu:
	$(SUDO) qemu-system-x86_64 -m 256 -hda /dev/sda -enable-kvm
