#!/bin/sh -e

opencrypt
mountrootfs "archlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Creating additional needed rootfs directories"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		mkdir -p /.btrfsroot
		mkdir -p /.snaps
		mkdir -p /boot/.snaps
		mkdir -p /home/.snaps
	_EOL
} >/dev/null 2>&1

info "Copying common configuration files"
{
	copychroot "lib/common/files" "/"
} >/dev/null 2>&1

info "Copying archlinux specific configuration files"
{
	copychroot "lib/flavors/archlinux/files" "/"
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
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/vconsole.conf"
			KEYMAP=${KEYMAP}
			FONT=Lat2-Terminus16
			FONT_MAP=
		EOL
	_EOL
} >/dev/null 2>&1

info "Configuring hostname"
{
	# In POSIX sh, HOSTNAME is undefined.
	# shellcheck disable=SC2039
	cmdchroot "printf '%s' '${HOSTNAME}' > /etc/hostname"
} >/dev/null 2>&1

info "Configuring hosts"
{
	# In POSIX sh, HOSTNAME is undefined.
	# shellcheck disable=SC2039
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/hosts"
			#<ip-address>   <hostname.domain.org>       <hostname>
			127.0.0.1       localhost.localdomain       localhost       ${HOSTNAME}
			::1             localhost.localdomain       localhost       ip6-localhost ${HOSTNAME}
		EOL
	_EOL
} >/dev/null 2>&1

info "Configuring sudoers"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		mkdir -p /etc/sudoers.d
		
		cat <<-EOL > "/etc/sudoers.d/${USER}"
			${USER} ALL=(ALL) NOPASSWD: ALL
		EOL
	_EOL
} >/dev/null 2>&1

info "Setting up users and groups"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-_EOP | passwd
			${ROOT_PASSWORD}
			${ROOT_PASSWORD}
		_EOP
		chsh -s /bin/bash
		
		# useradd -m -s /bin/bash -U \
		# 	-G adm,ftp,games,http,log,rfkill,sys,systemd-journal,uucp,wheel,audio,lp,network,optical,power,proc,scanner,storage,users,video \
		# "${USER}"
		
		
		useradd -m -s /bin/bash -U \
			-G adm,ftp,games,http,log,rfkill,sys,systemd-journal,uucp,wheel \
		"${USER}"
		
		cat <<-_EOP | passwd "${USER}"
			${USER_PASSWORD}
			${USER_PASSWORD}
		_EOP
	_EOL
} >/dev/null 2>&1

info "Generating fstab"
{
	# cmdchroot "genfstab -U / >> /etc/fstab"
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/fstab"
			# /dev/mapper/cryptroot
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /.btrfsroot btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/ 0 0
		
			UUID=$(deviceuuid "/dev/mapper/cryptroot") / btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/archlinux/@ 0 0
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /boot btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/archlinux/@boot 0 0
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /home btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/@home 0 0
		
		
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /.snaps btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/snaps/archlinux/@ 0 0
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /boot/.snaps btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/snaps/archlinux/@boot 0 0
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /home/.snaps btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/snaps/@home 0 0
		
			# $(partitionpath 2)
			UUID=$(deviceuuid "$(partitionpath 2)") /boot/efi vfat rw,noatime,fmask=0077,dmask=0077,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro 0 2
		
		
			# /dev/mapper/cryptswap
			UUID=$(deviceuuid "/dev/mapper/cryptswap") swap swap defaults 0 0
		
			# /proc with hidepid (https://wiki.archlinux.org/index.php/Security#hidepid)
			# proc /proc proc nodev,noexec,nosuid,hidepid=2,gid=proc 0 0
		EOL
		
		/usr/bin/cleanfstab > /dev/null 2>&1 && mv /etc/fstab.new /etc/fstab
	_EOL
} >/dev/null 2>&1

info "Configuring crypttab"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/crypttab"
			cryptroot UUID=$(deviceuuid "$(partitionpath 3)") /boot/crypt.key discard
			cryptswap UUID=$(deviceuuid "$(partitionpath 4)") /boot/crypt.key discard
		EOL
		
		cat <<-EOL > "/etc/crypttab.initramfs"
			cryptroot UUID=$(deviceuuid "$(partitionpath 3)") /boot/crypt.key discard
			cryptswap UUID=$(deviceuuid "$(partitionpath 4)") /boot/crypt.key discard
		EOL
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
		systemctl enable dhcpcd
		# systemctl enable systemd-swap
	_EOL
} >/dev/null 2>&1

info "Making pacman loving candy =)"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		sed -i 's@# Misc options@# Misc option\nILoveCandy@g' /etc/pacman.conf
		sed -i 's@#Color@Color@g' /etc/pacman.conf
	_EOL
} >/dev/null 2>&1

info "Installing and configuring yay aur helper"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cd /home/${USER}
		sudo -u ${USER} git clone https://aur.archlinux.org/yay.git
		cd yay
		sudo -u ${USER} makepkg --syncdeps --install --noconfirm
		rm -rf /home/${USER}/yay
	_EOL
} >/dev/null 2>&1

info "Configuring Xorg keyboard"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/X11/xorg.conf.d/20-keyboard.conf"
			Section "InputClass"
				Identifier "system-keyboard"
				MatchIsKeyboard "on"
				Driver "libinput"
				Option "XkbLayout" "${XKB_LAYOUT}"
				Option "XkbVariant" "${XKB_VARIANT}"
				Option "XkbOptions" "${XKB_OPTIONS}"
			EndSection
		
			Section "InputClass"
				Identifier "Default"
				MatchIsKeyboard "on"
				Driver "libinput"
				Option "XkbLayout" "${XKB_LAYOUT}"
				Option "XkbVariant" "${XKB_VARIANT}"
				Option "XkbOptions" "${XKB_OPTIONS}"
			EndSection
		EOL
		
		cat <<-EOL > "/etc/default/keyboard"
			XKBMODEL=""
			XKBLAYOUT="${XKB_LAYOUT}"
			XKBVARIANT="${XKB_VARIANT}"
			XKBOPTIONS="${XKB_OPTIONS}"
			BACKSPACE="guess"
		EOL
	_EOL
} >/dev/null 2>&1

info "Configuring Xorg server permissions"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		sed -i 's,needs_root_rights.*,needs_root_rights = no,g' "/etc/X11/Xwrapper.config"
		printf "%s" "allowed_users = anybody" >> /etc/X11/Xwrapper.config
	_EOL
} >/dev/null 2>&1

info "Updating everything again and finishing up"
{
	cmdchroot "yay -Syu --devel --timeupdate --noconfirm"
} >/dev/null 2>&1

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
