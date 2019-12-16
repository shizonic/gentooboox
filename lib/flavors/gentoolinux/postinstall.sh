#!/bin/sh -e

opencrypt
mountrootfs "gentoolinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Syncing the Gentoo repository"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		emerge-webrsync
	_EOL

} >/dev/null 2>&1

info "Setting up users"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		cat <<-_EOP | passwd
			${ROOT_PASSWORD}
			${ROOT_PASSWORD}
		_EOP
		chsh -s /bin/bash
		
		useradd -m -s /bin/bash -U \
			-G wheel,portage,audio,video,usb,cdrom \
			"${USER}"
		
		cat <<-_EOP | passwd "${USER}"
			${USER_PASSWORD}
			${USER_PASSWORD}
		_EOP
	_EOL
} >/dev/null 2>&1

# info "Installing required packages"
# {
# 	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
# 		source /etc/profile

# 		# echo "sys-apps/systemd cryptsetup" >> /etc/portage/package.use
# 		echo "sys-boot/grub device-mapper" >> /etc/portage/package.use
# 		echo "sys-fs/cryptsetup static kernel -gcrypt" >> /etc/portage/package.use
# 		echo "sys-kernel/genkernel-next cryptsetup" >> /etc/portage/package.use
# 		# echo "sys-kernel/dracut systemd device-mapper" >> /etc/portage/package.use

# 		echo "sys-fs/btrfs-progs ~amd64" >> /etc/portage/package.keywords
# 		echo "sys-boot/grub:2 ~amd64" >> /etc/portage/package.keywords
# 		echo "sys-fs/cryptsetup ~amd64" >> /etc/portage/package.keywords
# 		echo "sys-kernel/genkernel-next ~amd64" >> /etc/portage/package.keywords
# 		echo "sys-kernel/gentoo-sources ~amd64" >> /etc/portage/package.keywords

# 		emerge --verbose grub:2 cryptsetup genkernel-next btrfs-progs gentoo-sources
# 	_EOL
# } >/dev/null 2>&1

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
