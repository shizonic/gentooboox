#!/bin/sh -e

opencrypt
mountrootfs "voidlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Updating and installing packages"
{
	cmdchroot "printf \"%s\" \"Y\n\" | XBPS_ARCH=\"x86_64\" xbps-install \
			--yes \
			--sync \
			--update \
			--repository \"https://a-hel-fi.m.voidlinux.org/current\" \
			--repository \"https://a-hel-fi.m.voidlinux.org/current/nonfree\" \
			--repository \"https://a-hel-fi.m.voidlinux.org/current/multilib\" \
			--repository \"https://a-hel-fi.m.voidlinux.org/current/multilib/nonfree\" \
			$(readpkgs "voidlinux")"
} >/dev/null 2>&1

info "Installing grub bootloader"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		if ! grep -q "GRUB_ENABLE_CRYPTODISK" /etc/default/grub; then
			printf "%s\n" "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
		else
			sed -i 's,#GRUB_ENABLE_CRYPTODISK,GRUB_ENABLE_CRYPTODISK,g' /etc/default/grub
		fi
		
		# BIOS/MBR i386
		grub-install \
			--target=i386-pc \
			--root-directory="/" \
			--boot-directory="/boot" \
			--bootloader-id="Voidlinux_MBR" \
			--recheck \
			"${DISK}"
		
		# EFI i386
		grub-install \
			--target=i386-efi \
			--root-directory="/" \
			--boot-directory="/boot" \
			--efi-directory="/boot/efi" \
			--modules="part_gpt part_msdos" \
			--bootloader-id="Voidlinux_UEFI" \
			--removable \
			--recheck \
			"/dev/mapper/cryptroot"
		
		# EFI x86_64
		grub-install \
			--target=x86_64-efi \
			--root-directory="/" \
			--boot-directory="/boot" \
			--efi-directory="/boot/efi" \
			--modules="part_gpt part_msdos" \
			--bootloader-id="Voidlinux_UEFI" \
			--removable \
			--recheck \
			"/dev/mapper/cryptroot"
		
		mkdir -p /boot/grub/locale
		cp -f /usr/share/locale/en@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
	_EOL
} >/dev/null 2>&1

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
