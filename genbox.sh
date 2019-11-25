#!/bin/sh -e

die() {
    printf '\033[1;31m!>\033[m %s\n' "$@" >&2
    exit 1
}

log() {
    printf '\033[1;32m=>\033[m %s.\n' "$@"
}

info() {
    printf '\033[1;33m->\033[m %s.\n' "$@"
}

info_sub() {
    printf '\033[1;33m >\033[m %s.\n' "$@"
}

swapsize() {
    echo "x=l($(awk '/MemTotal/{printf "%s",  $2/1024/1024}' /proc/meminfo))/l(2); scale=0; 2^((x+0.5)/1)*2" | bc -l
}

genpasswd() {
    < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c 16
}

checkroot() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Must be run as root, exiting..."
    fi
}

usage() {
    cat <<_EOF
Usage: genbox.sh [options]

Options:
   -a --arch <arch>                       Set arch to use (x86_64 if unset).
   -d --disk <disk>                       Set disk to partition (/dev/sda if unset).
   -b --bios-part-size <bios-part-size>   Default bios partition size to use (2M if unset).
   -e --efi-part-size <efi-part-size>     Default efi partition size to use (512M if unset).
   -s --swap-part-size <swap-part-size>   Default swap partition to use (2x size of mem if unset).
   -r --root-part--size <root-part-size>  Default root partition size to use (rest of space if unset).
   -H --hostname <hostname>               Default hostname to use (xps if unset).
   -l --locale <locale>                   Default locale to use (en_US.UTF-8 if unset).
   -k --keymap <keymap>                   Default keymap to use (de_CH-latin1 if unset).
   -x --xkb-layout <xkb-layout>           XkbLayout to use (ch if unset).
   -X --xkb-variant <xkb-variant>         XkbVariant to use (de_nodeadkeys, if unset).
   -Z --xkb-options <xkb-options>         XkbOptions to use (default unset).
   -t --timezone <timezone>               Default timezone to use (Europe/Zurich if unset).
   -p --password <password>               Set root password (required).
   -u --user <user>                       Default user to create (tm if unset).
   -U --user-password <password>          Set user password (same as root password if unset).
   -P --luks-password <password>          Set LUKS password (same as root password if unset).
   -g --grub-user <grub-user>             Default GRUB user to create (same as user if unset).
   -G --grub-password <grub-password>     Set GRUB password (same as root password if unset).
   -D --disable-hostonly                  Disable dracut's hostonly (default unset).
   -Y --phases <pase phaseN>              Phases to run (all if unset).
   -B --btrfs-mount <mount-point>         Mount point for btrfs pool.
   -S --system-mount <mount-point>        Mount point for root system.
   -h --help                              Show this help.
_EOF
}

confirm() {
    cat <<_EOF
WARNING!
========
This will overwrite data on ${DISK} irrevocably.

    BTRFSMOUNT                 "${BTRFSMOUNT}"
    SYSTEMMOUNT                "${SYSTEMMOUNT}"
    ARCH                       "${ARCH}"
    DISK                       "${DISK}"
    BIOS_PART_SIZE             "${BIOS_PART_SIZE}"
    EFI_PART_SIZE              "${EFI_PART_SIZE}"
    SWAP_PART_SIZE             "${SWAP_PART_SIZE}"
    ROOT_PART_SIZE             "${ROOT_PART_SIZE}"
    HOSTNAME                   "${HOSTNAME}"
    LOCALE                     "${LOCALE}"
    KEYMAP                     "${KEYMAP}"
    XKB_LAYOUT                 "${XKB_LAYOUT}"
    XKB_VARIANT                "${XKB_VARIANT}"
    XKB_OPTIONS                "${XKB_OPTIONS}"
    TIMEZONE                   "${TIMEZONE}"
    GENTOOBOX_ROOT_PASSWORD    "${GENTOOBOX_ROOT_PASSWORD}"
    GENTOOBOX_USER             "${GENTOOBOX_USER}"
    GENTOOBOX_USER_PASSWORD    "${GENTOOBOX_USER_PASSWORD}"
    GENTOOBOX_LUKS_PASSWORD    "${GENTOOBOX_LUKS_PASSWORD}"
    GENTOOBOX_GRUB_USER        "${GENTOOBOX_GRUB_USER}"
    GENTOOBOX_GRUB_PASSWORD    "${GENTOOBOX_GRUB_PASSWORD}"
    DISABLE_HOST_ONLY          "${DISABLE_HOST_ONLY}"
    PHASES                     "${PHASES}"

Are you sure? (Type uppercase yes):
_EOF

    read -r answer
    if [ ! "${answer}" = "YES" ]; then
        die "Aborting due to user interaction..."
    fi
}

defaults() {
    TMPDIR="$(mktemp --directory --suffix ".gentoobox" 2> /dev/null || printf '%s' '/tmp/gentoobox')"

    : "${BTRFSMOUNT:="$(mktemp --directory --suffix=".btrfsroot" --tmpdir="/mnt" 2> /dev/null || printf "%s" "/mnt/gentoobox.btrfsmnt")"}"
    : "${SYSTEMMOUNT:="$(mktemp --directory --suffix=".systemroot" --tmpdir="/mnt" 2> /dev/null || printf "%s" "/mnt/gentoobox.systemmnt")"}"
    : "${ARCH:="x86_64"}"
    : "${DISK:="/dev/sda"}"
    : "${BIOS_PART_SIZE:="2M"}"
    : "${EFI_PART_SIZE:="512M"}"
    : "${SWAP_PART_SIZE:="$(swapsize)G"}"
    : "${ROOT_PART_SIZE:="0"}"
    : "${HOSTNAME:="gentoobox"}"
    : "${LOCALE:="en_US.UTF-8"}"
    : "${KEYMAP:="de_CH-latin1"}"
    : "${XKB_LAYOUT:="ch"}"
    : "${XKB_VARIANT:="de_nodeadkeys"}"
    : "${XKB_OPTIONS:=""}"
    : "${TIMEZONE:="Europe/Zurich"}"
    : "${GENTOOBOX_ROOT_PASSWORD:="$(genpasswd)"}"
    : "${GENTOOBOX_USER:="user"}"
    : "${GENTOOBOX_USER_PASSWORD:="${GENTOOBOX_ROOT_PASSWORD}"}"
    : "${GENTOOBOX_LUKS_PASSWORD:="${GENTOOBOX_ROOT_PASSWORD}"}"
    : "${GENTOOBOX_GRUB_USER:="${GENTOOBOX_USER}"}"
    : "${GENTOOBOX_GRUB_PASSWORD:="${GENTOOBOX_ROOT_PASSWORD}"}"
    : "${PHASES:="wipefs partition encrypt"}"
    : "${DISABLE_HOST_ONLY:=""}"
}

args() {
    param() {
        [ -n "${3}" ] && {
            eval "${1}=\"${3}\""
            shift
        } || die "${2} requires a non-empty option argument"
    }

    while [ -n "${1}" ]; do
        case "${1}" in
            -h|--help) usage; exit 0 ;;
            -a|--arch) param "ARCH" "${1}" "${2}" ;;
            -d|--disk) param "DISK" "${1}" "${2}" ;;
            -b|--bios-part-size) param "BIOS_PART_SIZE" "${1}" "${2}" ;;
            -e|--efi-part-size) param "EFI_PART_SIZE" "${1}" "${2}" ;;
            -s|--swap-part-size) param "SWAP_PART_SIZE" "${1}" "${2}" ;;
            -r|--root-part--size) param "ROOT_PART_SIZE" "${1}" "${2}" ;;
            -H|--hostname) param "HOSTNAME" "${1}" "${2}" ;;
            -l|--locale) param "LOCALE" "${1}" "${2}" ;;
            -k|--keymap) param "KEYMAP" "${1}" "${2}" ;;
            -x|--xkb-layout) param "XKB_LAYOUT" "${1}" "${2}" ;;
            -X|--xkb-variant) param "XKB_VARIANT" "${1}" "${2}" ;;
            -Z|--xkb-options) param "XKB_OPTIONS" "${1}" "${2}" ;;
            -t|--timezone) param "TIMEZONE" "${1}" "${2}" ;;
            -p|--password) param "GENTOOBOX_ROOT_PASSWORD" "${1}" "${2}" ;;
            -u|--user) param "GENTOOBOX_USER" "${1}" "${2}" ;;
            -U|--user-password) param "GENTOOBOX_USER_PASSWORD" "${1}" "${2}" ;;
            -P|--luks-password) param "GENTOOBOX_LUKS_PASSWORD" "${1}" "${2}" ;;
            -g|--grub-user) param "GENTOOBOX_GRUB_USER" "${1}" "${2}" ;;
            -G|--grub-password) param "GENTOOBOX_GRUB_PASSWORD" "${1}" "${2}" ;;
            -B|--btrfs-mount) param "BTRFSMOUNT" "${1}" "${2}" ;;
            -S|--system-mount) param "SYSTEMMOUNT" "${1}" "${2}" ;;
            -Y|--phases) param "PHASES" "${1}" "${2}" ;;
            -D|--disable-hostonly) param "DISABLE_HOST_ONLY" "${1}" "yes" ;;
        esac
        shift
    done

    unset -f param
}

cleanup() {
    for dir in ${TMPDIR} ${BTRFSMOUNT} ${SYSTEMMOUNT}; do
        rm -rf "${dir}"
    done
}

runphases() {
    for phase in ${PHASES}; do
        log "Running: ${phase}"
        eval "phase_${phase}"
    done
}

main() {
    args "${@}"

    trap 'cleanup' EXIT INT
    defaults
    confirm

    checkroot
    runphases
    cleanup
}

main "${@}"
