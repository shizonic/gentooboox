#!/bin/sh -e

opencrypt
mountrootfs "archlinux" "${MOUNTPOINT}"

info "Retreiving archlinux bootstrap tarball"
{
	wget --directory "${TMPDIR}" \
		"https://mirror.puzzle.ch/archlinux/iso/2019.12.01/archlinux-bootstrap-2019.12.01-x86_64.tar.gz"
} >/dev/null 2>&1

info "Extracting archlinux bootstrap tarball"
{
	tar xzfv "${TMPDIR}"/archlinux-bootstrap-*.tar.gz \
		--xattrs-include="*.*" \
		--numeric-owner \
		-C "${TMPDIR}"
} >/dev/null 2>&1

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

unmountrootfs "${MOUNTPOINT}"
closecrypt
