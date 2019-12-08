#!/bin/sh -e

opencrypt
mountrootfs "gentoolinux" "${MOUNTPOINT}"

info "Extracting stage 3"
{
	tar xpvf "${TMPDIR}"/stage3-*.tar.xz \
		--xattrs-include="*.*" \
		--numeric-owner \
		-C "${MOUNTPOINT}"
}

umountrootfs "${MOUNTPOINT}"
closecrypt
