SUDO := sudo

format:
	shfmt -l -w linbox.sh lib/*/*.sh

qemu:
	$(SUDO) qemu-system-x86_64 -m 256 -hda /dev/sda -enable-kvm

shellcheck:
	shellcheck --exclude=SC1090,SC2039 linbox.sh lib/*/*.sh

formatcheck:
	shfmt -d linbox.sh lib/*/*.sh
