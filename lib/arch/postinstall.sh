#!/bin/sh -e

opencrypt
mountsubvols "${MOUNTPOINT}"
mountpseudofs "${MOUNTPOINT}"

info "Initialize pacman keyring"
cmdchroot "pacman-key --init && pacman-key --populate"

info "Updating and installing base system and required packages"
cmdchroot "pacman -Syyu --noconfirm --needed \
    acpi \
    arch-install-scripts \
    base \
    base-devel \
    bash-completion \
    btrfs-progs \
    ca-certificates \
    cdrtools \
    crda \
    dhclient \
    dialog \
    dnscrypt-proxy \
    dosfstools \
    dvd+rw-tools \
    ed \
    efibootmgr \
    ethtool \
    expect \
    gptfdisk \
    grub \
    haveged \
    iproute2 \
    iw \
    kbd \
    lynx \
    lz4 \
    net-tools \
    nftables \
    openresolv \
    openssh \
    pacman-contrib \
    rsync \
    systemd-swap \
    tmux \
    unzip \
    vim \
    wget \
    wireguard-arch \
    wireguard-tools \
    wireless-regdb \
    wireless_tools \
    wpa_supplicant \
    zip"

umountsubvols "${MOUNTPOINT}"
unmountpseudofs "${MOUNTPOINT}"
closecrypt
