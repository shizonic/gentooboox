#!/bin/sh -e

opencrypt
mountrootfs "archlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Copying archlinux rootfs"
{
	copychroot "${TMPDIR}/root.x86_64" "/"
} >/dev/null 2>&1

info "Removing unused files from rootfs"
{
	cmdchroot "rm -f /README"
} >/dev/null 2>&1

info "Copying crypt.key file"
{
	copychroot "${TMPDIR}/crypt" "/boot"
} >/dev/null 2>&1

info "Backing up pacman mirrorlist"
{
	cmdchroot "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bkp"
} >/dev/null 2>&1

info "Copying pacman mirror list to rootfs"
{
	copychroot "lib/flavors/archlinux/files/etc/pacman.d" "/etc/pacman.d"
} >/dev/null 2>&1

info "Initialize pacman keyring"
{
	cmdchroot "pacman-key --init && pacman-key --populate"
} >/dev/null 2>&1

info "Updating and installing base system and required packages"
{
	cmdchroot "pacman -Syyu --noconfirm --needed \
		acpi \
		arch-install-scripts \
		base \
		base-devel \
		bash-completion \
		btrfs-progs \
		ca-certificates \
		cdrtools \
		crda \
		dhclient \
		dialog \
		dnscrypt-proxy \
		dosfstools \
		dvd+rw-tools \
		ed \
		efibootmgr \
		ethtool \
		expect \
		gptfdisk \
		grub \
		haveged \
		iproute2 \
		iw \
		kbd \
		lynx \
		lsof \
		lz4 \
		net-tools \
		nftables \
		openresolv \
		openssh \
		pacman-contrib \
		rsync \
		systemd-swap \
		tmux \
		unzip \
		vim \
		wget \
		wireguard-arch \
		wireguard-tools \
		wireless-regdb \
		wireless_tools \
		wpa_supplicant \
		xz \
		zip"
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
	_EOL
} >/dev/null 2>&1

info "Cleaning up"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		# needed to be able to successfully unmount pseudofs
		pkill gpg-agent ||:
		pkill dirmngr   ||:
	_EOL
} >/dev/null 2>&1

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
