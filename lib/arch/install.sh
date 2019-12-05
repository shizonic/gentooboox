#!/bin/sh -e

info "Extracting archlinux bootstrap tarball"; {
	tar xzfv "${TMPDIR}"/archlinux-bootstrap-*.tar.gz \
		--xattrs-include="*.*" \
		--numeric-owner \
		-C "${TMPDIR}"
}

opencrypt
mountrootfs "${MOUNTPOINT}"

info "Copying archlinux rootfs"; {
	copychroot "${TMPDIR}/root.x86_64" "/"
}

info "Copying crypt.key file"; {
	copychroot "${TMPDIR}/crypt" "/boot"
}

info "Removing unused files from rootfs"; {
	cmdchroot "rm -f /README"
}

info "Backing up pacman mirrorlist"; {
	cmdchroot "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bkp"
}

info "Setting up pacman mirrorlist to switzerland"; {
	cat <<-'_EOL' > "${MOUNTPOINT}/etc/pacman.d/mirrorlist"
		##
		## Arch Linux repository mirrorlist
		## Generated on 2019-10-01
		##

		## Worldwide
		#Server = http://mirrors.evowise.com/archlinux/$repo/os/$arch
		#Server = http://mirror.rackspace.com/archlinux/$repo/os/$arch
		#Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch

		## Switzerland
		Server = http://pkg.adfinis-sygroup.ch/archlinux/$repo/os/$arch
		Server = https://pkg.adfinis-sygroup.ch/archlinux/$repo/os/$arch
		Server = http://mirror.init7.net/archlinux/$repo/os/$arch
		Server = https://mirror.init7.net/archlinux/$repo/os/$arch
		Server = http://mirror.puzzle.ch/archlinux/$repo/os/$arch
		Server = https://mirror.puzzle.ch/archlinux/$repo/os/$arch
		Server = https://mirror.ungleich.ch/mirror/packages/archlinux/$repo/os/$arch
	_EOL
}

umountrootfs "${MOUNTPOINT}"
closecrypt
