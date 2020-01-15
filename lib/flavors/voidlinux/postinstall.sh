#!/bin/sh -e

opencrypt
mountrootfs "voidlinux" "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Copying common configuration files"
{
	copychroot "lib/common/files" "/"
} >/dev/null 2>&1

info "Copying voidlinux specific configuration files"
{
	copychroot "lib/flavors/voidlinux/files" "/"
} >/dev/null 2>&1

info "Configuring rc configuration"
{
	# In POSIX sh, HOSTNAME is undefined.
	# shellcheck disable=SC2039
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		sed -i \
			-e "s,#HOSTNAME=.*,HOSTNAME=\"${HOSTNAME}\"," \
			-e "s,#HARDWARECLOCK=.*,HARDWARECLOCK=\"UTC\"," \
			-e "s,#TIMEZONE=.*,TIMEZONE=\"${TIMEZONE}\"," \
			-e "s,#KEYMAP=.*,KEYMAP=\"${KEYMAP}\"," \
			-e "s,#FONT=.*,FONT=\"Lat2-Terminus16\"," \
			-e "s,#TTYS=.*,TTYS=2," \
		"/etc/rc.conf"
	_EOL
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
		sed -i "s,#${LOCALE},${LOCALE}," "/etc/default/libc-locales"
		xbps-reconfigure -f glibc-locales
		
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
		
		useradd -m -s /bin/bash -U \
			-G wheel,users,audio,video,cdrom,dialout,floppy,input,kvm,lp,mail,network,optical,scanner,socklog,storage,xbuilder,bluetooth \
		"${USER}"
		
		cat <<-_EOP | passwd "${USER}"
			${USER_PASSWORD}
			${USER_PASSWORD}
		_EOP
		
		groupadd adbusers
		groupadd proc
		usermod -a -G adbusers "${USER}"
		usermod -a -G proc "${USER}"
	_EOL
} >/dev/null 2>&1

info "Generating fstab"
{
	# cmdchroot "genfstab -U / >> /etc/fstab"
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/fstab"
			# /dev/mapper/cryptroot
			UUID=$(deviceuuid "/dev/mapper/cryptroot") / btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/voidlinux/@ 0 0
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /boot btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/@boot 0 0
			UUID=$(deviceuuid "/dev/mapper/cryptroot") /home btrfs rw,noatime,compress=lzo,ssd,discard,space_cache,subvol=/subvols/@home 0 0
		
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
			# If one would like to use crypttab
			cryptroot UUID=$(deviceuuid "$(partitionpath 3)") /boot/crypt.key discard
			cryptswap UUID=$(deviceuuid "$(partitionpath 4)") /boot/crypt.key discard
		EOL
	_EOL
} >/dev/null 2>&1

info "Configuring dracut"
{
	# In POSIX sh, HOSTNAME is undefined.
	# shellcheck disable=SC2039
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-EOL > "/etc/dracut.conf.d/${HOSTNAME}.conf"
			#####################################
			# MISC
			##
			tmpdir="/tmp"
			hostonly="yes"
			hostonly_cmdline="no"
		
			#####################################
			# LOGGING
			##
			logfile=/var/log/dracut.log
			fileloglvl=6
		
			#####################################
			# DISABLE UNUSED CONFIGS
			##
			mdadmconf="no"
			lvmconf="no"
		
			#####################################
			# USE FSTAB
			##
			#use_fstab="yes"
			#add_fstab+=" /etc/fstab "
		
			#####################################
			# MODULES
			##
			add_dracutmodules+=" crypt dm btrfs resume "
			omit_dracutmodules+=" bash systemd plymouth "
			show_modules="yes"
		
			#####################################
			# ITEMS
			##
			install_items+=" /etc/crypttab /boot/crypt.key "
		
			#####################################
			# DEVICES
			##
			add_device+=" /dev/mapper/cryptswap "
		
			#####################################
			# CMDLINE : DEBUGGING
			##
			#kernel_cmdline+=" rd.shell rd.debug log_buf_len=1M "
		
			#####################################
			# CMDLINE : PERFORMANCE
			##
			kernel_cmdline+=" rd.md=0 rd.dm=0 rd.lvm=0 "
		
			#####################################
			# CMDLINE : ROOT
			##
			kernel_cmdline+=" rootfstype=btrfs root=UUID=$(deviceuuid "$(partitionpath 3)") "
			kernel_cmdline+=" rootflags=rw,noatime,compress=lzo,ssd,discard,space_cache "
			kernel_cmdline+=" resume=UUID=$(deviceuuid "/dev/mapper/cryptswap") "
		
			#####################################
			# CMDLINE : KEYMAP
			##
			kernel_cmdline+=" vconsole.unicode=1 rd.vconsole.keymap=${KEYMAP} rd.vconsole.font=Lat2-Terminus16 "
		
			#####################################
			# CMDLINE : LOCALE
			##
			kernel_cmdline+=" rd.locale.LANG=${LOCALE} "
		
			#####################################
			# CMDLINE: CRYPTO
			##
			kernel_cmdline+=" rd.luks=1 rd.luks.allow-discards "
		
			# if one wants to use hostonly="no", comment these lines out ...
			kernel_cmdline+=" rd.luks.uuid=$(deviceuuid "$(partitionpath 3)") "
			kernel_cmdline+=" rd.luks.name=$(deviceuuid "$(partitionpath 3)")=cryptroot "
			kernel_cmdline+=" rd.luks.key=/boot/crypt.key:UUID=$(deviceuuid "$(partitionpath 3)") "
			kernel_cmdline+=" rd.luks.uuid=$(deviceuuid "$(partitionpath 4)") "
			kernel_cmdline+=" rd.luks.name=$(deviceuuid "$(partitionpath 4)")=cryptswap "
		
			# ... and this one in
			#kernel_cmdline+=" rd.auto rd.luks.crypttab=1 rd.luks.allow-discards rd.luks.key=/boot/crypt.key "
		EOL
		
		xbps-reconfigure -f "$(
		xbps-query \
		--property=pkgver linux |
		cut -d '_' -f 1 | sed 's,-,,'
		)"
	_EOL
} >/dev/null 2>&1

info "Configuring grub"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		grub-mkconfig -o /boot/grub/grub.cfg
	_EOL
} >/dev/null 2>&1

info "Disabling unused services"
{
	# n is referenced but not assigned.
	# shellcheck disable=SC2154
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		rm -f /var/service/agetty-tty*
		for n in 3 4 5 6; do
			touch /etc/sv/agetty-tty${n}
		done
	_EOL
} >/dev/null 2>&1

info "Configuring dhcpcd"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		cat <<-_EOF >> "/etc/dhcpcd.conf"
		
			# Speed up DHCP by disabling ARP probing
			noarp
		_EOF
	_EOL
} >/dev/null 2>&1

info "Configuring zramen"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		sed -i "s,zramen make.*,zramen make > /dev/null 2&>1," "/etc/sv/zramen/run"
		sed -i "s,zramen toss.*,zramen toss > /dev/null 2&>1," "/etc/sv/zramen/finish"
	_EOL
} >/dev/null 2>&1

info "Enabling runit services"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		ln -sf /etc/sv/acpid /var/service
		ln -sf /etc/sv/agetty-tty1 /var/service
		ln -sf /etc/sv/agetty-tty2 /var/service
		ln -sf /etc/sv/alsa /var/service
		ln -sf /etc/sv/bluetoothd /var/service
		ln -sf /etc/sv/chronyd /var/service
		ln -sf /etc/sv/cronie /var/service
		ln -sf /etc/sv/cupsd /var/service
		ln -sf /etc/sv/dbus /var/service
		ln -sf /etc/sv/dhcpcd /var/service
		ln -sf /etc/sv/nanoklogd /var/service
		ln -sf /etc/sv/nftables /var/service
		ln -sf /etc/sv/smartd /var/service
		ln -sf /etc/sv/socklog-unix /var/service
		ln -sf /etc/sv/udevd /var/service
		ln -sf /etc/sv/wpa_supplicant /var/service
		ln -sf /etc/sv/zramen /var/service
		# ln -sf /etc/sv/mcelog /var/service
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

unmountpseudofs "${MOUNTPOINT}"
unmountrootfs "${MOUNTPOINT}"
closecrypt
