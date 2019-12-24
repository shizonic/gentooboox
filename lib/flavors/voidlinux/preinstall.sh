#!/bin/sh -e

opencrypt
mountrootfs "voidlinux" "${MOUNTPOINT}"

info "Retreiving voidlinux rootfs tarball"
{
	wget --directory "${TMPDIR}" \
		"https://a-hel-fi.m.voidlinux.org/live/current/void-x86_64-ROOTFS-20181111.tar.xz"
} >/dev/null 2>&1

info "Extracting voidlinux bootstrap tarball"
{
	tar xpvf "${TMPDIR}"/void-*.tar.xz \
		--xattrs-include="*.*" \
		--numeric-owner \
		-C "${MOUNTPOINT}"
} >/dev/null 2>&1

info "Copying crypt.key file"
{
	copychroot "${TMPDIR}/crypt" "/boot"
} >/dev/null 2>&1

info "Copying xbps keys"
{
	copychroot "lib/flavors/voidlinux/files/var" "/var"
} >/dev/null 2>&1

unmountrootfs "${MOUNTPOINT}"
closecrypt
