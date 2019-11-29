#!/bin/sh -e

opencrypt
mountsubvols "${MOUNTPOINT}"

info "Extracting stage 3"
tar xpvf "${TMPDIR}"/stage3-*.tar.xz \
    --xattrs-include="*.*" \
    --numeric-owner \
    -C "${MOUNTPOINT}"

umountsubvols "${MOUNTPOINT}"
closecrypt
