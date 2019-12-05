#!/bin/sh -e

info "Retreiving stage 3 tarball"
wget --directory "${TMPDIR}" \
    "http://distfiles.gentoo.org/releases/amd64/autobuilds/20191124T214502Z/stage3-amd64-20191124T214502Z.tar.xz"
