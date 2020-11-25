#!/bin/sh -e

opencrypt
mountrootfs "archlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Initialize pacman keyring"
{
	cmdchroot "pacman-key --init && pacman-key --populate"

	# needed to be able to successfully unmount pseudofs
	kill -9 "$(pidof gpg-agent)"
} >/dev/null 2>&1

info "Updating and installing packages"
{
	cmdchroot "pacman -Syyu --noconfirm --needed $(readpkgs "archlinux")"
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
			--bootloader-id="Archlinux_MBR" \
			--recheck \
			"${DISK}"
		
		# EFI i386
		grub-install \
			--target=i386-efi \
			--root-directory="/" \
			--boot-directory="/boot" \
			--efi-directory="/boot/efi" \
			--modules="part_gpt part_msdos" \
			--bootloader-id="Archlinux_UEFI" \
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
			--bootloader-id="Archlinux_UEFI" \
			--removable \
			--recheck \
			"/dev/mapper/cryptroot"
		
		mkdir -p /boot/grub/locale
		cp -f /usr/share/locale/en@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
		
		# fix virtualbox uefi
		# echo "fs0:\EFI\BOOT\BOOTX64.EFI" >> /boot/efi/startup.nsh
	_EOL
} >/dev/null 2>&1

info "Cleaning and finishing up"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		# root top dir permissions are wrong by default
		chmod 755 /
	_EOL
} >/dev/null 2>&1

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
