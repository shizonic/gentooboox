SUDO := sudo

shellcheck:
	shellcheck --exclude=SC1090,SC2039 linbox.sh lib/*/*.sh

qemu:
	$(SUDO) qemu-system-x86_64 -m 256 -hda /dev/sda -enable-kvm
