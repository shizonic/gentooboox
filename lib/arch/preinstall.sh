#!/bin/sh -e

info "Retreiving archlinux bootstrap tarball"
wget --directory "${TMPDIR}" \
    "https://mirror.puzzle.ch/archlinux/iso/2019.12.01/archlinux-bootstrap-2019.12.01-x86_64.tar.gz"
