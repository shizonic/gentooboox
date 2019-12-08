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
}

info "Setting up users"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		cat <<-_EOP | passwd
			${LINBOX_ROOT_PASSWORD}
			${LINBOX_ROOT_PASSWORD}
		_EOP
		chsh -s /bin/bash
		
		useradd -m -s /bin/bash -U \
			-G wheel,portage,audio,video,usb,cdrom \
			"${LINBOX_USER}"
		
		cat <<-_EOP | passwd "${LINBOX_USER}"
			${LINBOX_USER_PASSWORD}
			${LINBOX_USER_PASSWORD}
		_EOP
	_EOL
}

info "Configure timezone and hardware clock"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
		printf "%s" "${TIMEZONE}" > /etc/timezone
		sed -i "s,clock=.*,clock=\"UTC\",g" /etc/conf.d/hwclock
		
		emerge --config sys-libs/timezone-data
	_EOL
}

info "Configure locales"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		sed -i 's,#${LOCALE},${LOCALE},g' /etc/locale.gen
		cat <<-_EOP > /etc/locale.conf
			LANG="${LOCALE}"
			LC_COLLATE="C"
		_EOP
		cat <<-_EOP > /etc/env.d/02locale
			LANG="${LOCALE}"
			LC_COLLATE="C"
		_EOP
		
		locale-gen
	_EOL
}

info "Configure host and domain name"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		printf "%s" "${HOSTNAME}" > /etc/hostname
		sed -i "s,hostname=.*,hostname=\"${HOSTNAME}\",g" \
			/etc/conf.d/hostname
	_EOL
}

info "Configure keymap and console font"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		sed -i "s,keymap=.*,keymap=\"${KEYMAP}\",g" \
			/etc/conf.d/keymaps
		sed -i "s,consolefont=.*,consolefont=\"Lat2-Terminus16\",g" \
			/etc/conf.d/consolefont
		cat <<-_EOP > /etc/vconsole.conf
			KEYMAP=${KEYMAP}
			FONT=Lat2-Terminus16
		_EOP
	_EOL
}

info "Installing required packages"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		# echo "sys-apps/systemd cryptsetup" >> /etc/portage/package.use
		echo "sys-boot/grub device-mapper" >> /etc/portage/package.use
		echo "sys-fs/cryptsetup static kernel -gcrypt" >> /etc/portage/package.use
		echo "sys-kernel/genkernel-next cryptsetup" >> /etc/portage/package.use
		# echo "sys-kernel/dracut systemd device-mapper" >> /etc/portage/package.use
		
		echo "sys-fs/btrfs-progs ~amd64" >> /etc/portage/package.keywords
		echo "sys-boot/grub:2 ~amd64" >> /etc/portage/package.keywords
		echo "sys-fs/cryptsetup ~amd64" >> /etc/portage/package.keywords
		echo "sys-kernel/genkernel-next ~amd64" >> /etc/portage/package.keywords
		echo "sys-kernel/gentoo-sources ~amd64" >> /etc/portage/package.keywords
		
		emerge --verbose grub:2 cryptsetup genkernel-next btrfs-progs gentoo-sources
	_EOL
}

info "Updating environment"
{
	cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
		source /etc/profile
		
		env-update
	_EOL
}

umountrootfs "${MOUNTPOINT}"
unmountpseudofs "${MOUNTPOINT}"
closecrypt
