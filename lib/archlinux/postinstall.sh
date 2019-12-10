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
		zip"
} >/dev/null 2>&1

info "Copying configuration files to rootfs"
{
	copychroot "lib/archlinux/files" "/"
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

info "Generating fstab"
{
	cmdchroot "genfstab -U / >> /etc/fstab"

	cat <<-_EOL >>"${MOUNTPOINT}/etc/fstab"
		# /proc with hidepid (https://wiki.archlinux.org/index.php/Security#hidepid)
		proc                                      /proc       proc        nodev,noexec,nosuid,hidepid=2,gid=proc 0 0
	_EOL

	cmdchroot "/usr/bin/cleanfstab > /dev/null 2>&1 && mv /etc/fstab.new /etc/fstab"
} >/dev/null 2>&1

info "Configuring timezone and hardware clock"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
		hwclock --systohc --utc
	_EOL
} >/dev/null 2>&1

info "Configuring locale"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		sed -i 's,#${LOCALE} UTF-8,${LOCALE} UTF-8),g' /etc/locale.gen
		locale-gen
		
		cat <<-EOL > "/etc/locale.conf"
			LANG=${LOCALE}
			LC_COLLATE=C
		EOL
	_EOL
} >/dev/null 2>&1

info "Configuring keymap"
{
	cat <<-_EOL >"${MOUNTPOINT}/etc/vconsole.conf"
		KEYMAP=${KEYMAP}
		FONT=Lat2-Terminus16
		FONT_MAP=
	_EOL
} >/dev/null 2>&1

info "Configuring hostname"
{
	cat <<-_EOL >"${MOUNTPOINT}/etc/hostname"
		${HOSTNAME}
	_EOL
} >/dev/null 2>&1

info "Configuring hosts"
{
	cat <<-_EOL >"${MOUNTPOINT}/etc/hosts"
		#<ip-address>   <hostname.domain.org>       <hostname>
		127.0.0.1       localhost.localdomain       localhost       ${HOSTNAME}
		::1             localhost.localdomain       localhost       ip6-localhost ${HOSTNAME}
	_EOL
} >/dev/null 2>&1

info "Configuring sudoers"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		mkdir -p /etc/sudoers.d
		
		cat <<-EOL > "/etc/sudoers.d/${LINBOX_USER}"
			${LINBOX_USER} ALL=(ALL) NOPASSWD: ALL
		EOL
	_EOL
} >/dev/null 2>&1

info "Setting up users and groups"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-_EOP | passwd
			${LINBOX_ROOT_PASSWORD}
			${LINBOX_ROOT_PASSWORD}
		_EOP
		chsh -s /bin/bash
		
		useradd -m -s /bin/bash -U \
			-G adm,ftp,games,http,log,rfkill,sys,systemd-journal,uucp,wheel \
		"${LINBOX_USER}"
		
		cat <<-_EOP | passwd "${LINBOX_USER}"
			${LINBOX_USER_PASSWORD}
			${LINBOX_USER_PASSWORD}
		_EOP
	_EOL
} >/dev/null 2>&1

info "Configuring crypttab"
{
	cat <<-_EOL >>"${MOUNTPOINT}/etc/crypttab"
		# If one would like to use crypttab
		# cryptroot UUID=$(deviceuuid "$(partitionpath 3)") /boot/crypt.key discard
		# cryptswap UUID=$(deviceuuid "$(partitionpath 4)") /boot/crypt.key discard
	_EOL

	cat <<-_EOL >>"${MOUNTPOINT}/etc/crypttab.initramfs"
		# If one would like to use crypttab
		# cryptroot UUID=$(deviceuuid "$(partitionpath 3)") /boot/crypt.key discard
		# cryptswap UUID=$(deviceuuid "$(partitionpath 4)") /boot/crypt.key discard
	_EOL
} >/dev/null 2>&1

info "Configuring mkinitcpio"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		# systemd initramfs
		# sed -i 's,HOOKS=.*,HOOKS=\(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt openswap filesystems fsck\),g' /etc/mkinitcpio.conf
		
		# busybox initramfs
		sed -i 's,HOOKS=.*,HOOKS=\(base udev autodetect keyboard keymap consolefont modconf block encrypt openswap resume filesystems fsck\),g' /etc/mkinitcpio.conf
		
		sed -i 's,MODULES=.*,MODULES=\(crc32c-intel i915\),g' /etc/mkinitcpio.conf
		
		sed -i 's,BINARIES=.*,BINARIES=\(/usr/bin/btrfs\),g' /etc/mkinitcpio.conf
		
		# sed -i 's,FILES=.*,FILES=\(/boot/crypt.key /etc/crypttab\),g' /etc/mkinitcpio.conf
		sed -i 's,FILES=.*,FILES=\(/boot/crypt.key /etc/modprobe.d/modprobe.conf\),g' /etc/mkinitcpio.conf
		
		sed -i 's,@@CRYPTSWAP_UUID@@,$(deviceuuid "$(partitionpath 4)"),g' /etc/initcpio/hooks/openswap
		sed -i 's,@@CRYPTSWAP_UUID@@,$(deviceuuid "$(partitionpath 4)"),g' /etc/initcpio/install/openswap
		
		mkinitcpio -p linux
	_EOL
} >/dev/null 2>&1

info "Configuring grub"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		# systemd initramfs
		# sed -i 's#GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX="root=/dev/mapper/cryptroot rootfstype=btrfs rootflags=rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/archlinux/@ rd.luks.name=$(deviceuuid "$(partitionpath 3)")=cryptroot rd.luks.name=$(deviceuuid "$(partitionpath 4)")=cryptswap rd.luks.key=/boot/crypt.key rd.luks.options=discard resume=UUID=$(deviceuuid "/dev/mapper/cryptswap")"#g' /etc/default/grub
		
		# sed -i 's#GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX="luks.name=$(deviceuuid "$(partitionpath 3)")=cryptroot luks.name=$(deviceuuid "$(partitionpath 4)")=cryptswap luks.key=/boot/crypt.key luks.options=discard rootfstype=btrfs root=/dev/mapper/cryptroot rootflags=subvol=/subvols/archlinux/@ resume=/dev/mapper/cryptswap"#g' /etc/default/grub
		
		# busybox initramfs
		sed -i 's#GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX="root=/dev/mapper/cryptroot rootfstype=btrfs rootflags=rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/archlinux/@ cryptdevice=UUID=$(deviceuuid "$(partitionpath 3)"):cryptroot:allow-discards cryptkey=rootfs:/boot/crypt.key resume=/dev/mapper/cryptswap"#g' /etc/default/grub
		
		grub-mkconfig -o /boot/grub/grub.cfg
	_EOL
} >/dev/null 2>&1

info "Enabling systemd services"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		systemctl enable dnscrypt-proxy.service
		systemctl enable nftables
		systemctl enable systemd-swap
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
