#!/bin/sh -e

opencrypt
mountsubvols "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Syncing the Gentoo repository"
cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
    source /etc/profile
    emerge-webrsync
_EOL

info "Setting up users"
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

info "Installing required packages"
cat <<-_EOL | chroot "${MOUNTPOINT}" /bin/sh
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

umountsubvols "${MOUNTPOINT}"
unmountpseudofs "${MOUNTPOINT}"
closecrypt
