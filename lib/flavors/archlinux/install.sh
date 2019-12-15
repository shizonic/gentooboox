#!/bin/sh -e

opencrypt
mountrootfs "archlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

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
		dhcpcd \
		dialog \
		dnscrypt-proxy \
		dosfstools \
		dvd+rw-tools \
		ed \
		efibootmgr \
		ethtool \
		expect \
		git \
		go \
		gptfdisk \
		grub \
		haveged \
		intel-ucode \
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
		python \
		python2 \
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
		zip \
		zsh \
		zsh-completions"
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

info "Cleaning and finishing up"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		# root top dir permissions are wrong by default
		chmod 755 /
		
		# needed to be able to successfully unmount pseudofs
		pkill gpg-agent ||:
		pkill dirmngr   ||:
	_EOL
} >/dev/null 2>&1

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
