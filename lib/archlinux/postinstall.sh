#!/bin/sh -e

opencrypt
mountrootfs "archlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Initialize pacman keyring"
{
	cmdchroot "pacman-key --init && pacman-key --populate"
}

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
		zip"
}

info "Copying configuration files to rootfs"
{
	copychroot "lib/${FLAVOR}/files" "/"
}

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
	_EOL
}

info "Configuring mkinitcpio config"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		# sed -i 's,HOOKS=.*,HOOKS=\(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck\),g' /etc/mkinitcpio.conf
		
		sed -i 's,HOOKS=.*,HOOKS=\(base systemd autodetect keyboard modconf block sd-encrypt filesystems fsck\),g' /etc/mkinitcpio.conf
		
		sed -i 's,FILES=.*,FILES=\(/boot/crypt.key\),g' /etc/mkinitcpio.conf
		
		mkinitcpio -p linux
	_EOL
}

info "Configuring grub config"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		sed -i 's,GRUB_CMDLINE_LINUX=.*,GRUB_CMDLINE_LINUX="root=/dev/mapper/cryptroot rootflags=subvol=/subvols/@ rd.luks=$(partitionpath 3):cryptswap rd.luks=$(partitionpath 3):cryptroot rd.luks.key=/boot/crypt.key",g' /etc/default/grub
		
		grub-mkconfig -o /boot/grub/grub.cfg
	_EOL
}

umountrootfs "${MOUNTPOINT}"
unmountpseudofs "${MOUNTPOINT}"
closecrypt
