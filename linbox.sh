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

partitionpath() {
	printf "%s" "$(sfdisk -l "${DISK}" | awk '/^\/dev/ {print $1}' | grep "${1}$")"
}

opencrypt() {
	# swap partition
	if ! cryptsetup status "cryptswap" > /dev/null 2>&1; then
		cryptsetup \
			--key-file "/${TMPDIR}/.crypt.key" \
			luksOpen "$(partitionpath 4)" \
			"cryptswap"
	fi

	# root partition
	if ! cryptsetup status "cryptroot" > /dev/null 2>&1; then
		cryptsetup \
			--key-file "/${TMPDIR}/.crypt.key" \
			luksOpen "$(partitionpath 3)" \
			"cryptroot"
	fi
}

closecrypt() {
	# swap partition
	if cryptsetup status "cryptswap" > /dev/null 2>&1; then
		cryptsetup luksClose "cryptswap"
	fi

	# root partition
	if cryptsetup status "cryptroot" > /dev/null 2>&1; then
		cryptsetup luksClose "cryptroot"
	fi
}

mountsubvol() {
	mount_opts="compress=lzo,noatime,rw,space_cache,ssd,discard,subvol=${1}"

	# mount root
	mkdir -p "${2}"
	if ! mountpoint -q "${2}"; then
		mount \
			--types "btrfs" \
			--options "${mount_opts}" \
			"/dev/mapper/cryptroot" \
			"${2}"
	fi
}

mountsubvols() {
	mountsubvol "/subvols/@" "${1}"
	mountsubvol "/subvols/@boot" "${1}/boot"
	mountsubvol "/subvols/@home" "${1}/home"
}

umountsubvols() {
	unmount "${1}/boot"
	unmount "${1}/home"
	unmount "${1}"
}

mountpseudofs() {
	for f in sys dev proc run tmp; do
		if ! mountpoint -q "${1}/${f}"; then
			mkdir -p "${1}/${f}"
			mount --rbind "/${f}" "${1}/${f}"
			mount --make-rslave "${1}/${f}"
		fi
	done

	if ! mountpoint -q "${1}"/etc/resolv.conf; then
		mkdir -p "${1}/etc"
		touch "${1}/etc/resolv.conf"
		mount --bind "/etc/resolv.conf" "${1}/etc/resolv.conf"
	fi

	if [ -e /sys/firmware/efi/systab ] && ! mountpoint -q "${1}/sys/firmware/efi/efivars"; then
		mkdir p "${1}/sys/firmware/efi/efivars"
		mount -t efivarfs efivarfs "${1}/sys/firmware/efi/efivars"
	fi
}

unmountpseudofs() {
	for f in sys dev proc run tmp; do
		unmount "${1}/${f}"
	done
	unmount "${1}/etc/resolv.conf"
	unmount "${1}/sys/firmware/efi/efivars"
}

unmount() {
	if mountpoint -q "${1}"; then
		umount -R "${1}"
	fi
}

checkroot() {
	if [ "$(id -u)" -ne 0 ]; then
		die "Must be run as root, exiting..."
	fi
}

cmdchroot() {
    chroot "${MOUNTDIR}" sh -c "${@}"
}

copychroot() {
    [ ! -d "${1}" ] && \
        mkdir -p "${1}"
    find "${1}" -mindepth 1 -maxdepth 1 -exec \
        cp  --recursive \
            --force \
            --preserve \
            --no-preserve ownership \
            -P \
        {} "${MOUNTDIR}/${2}" \;
}

usage() {
	cat <<_EOF
Usage: linbox.sh [options]

Options:
   -f --flavor                            Set the distro flavor (gentoo, void, arch).
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
   -Y --phases <pase phaseN>              Phases to run (all if unset).
   -M --mountpoint <mount-point>          Mount point for btrfs pool.
   -T --tmpdir <tmp-dir>                  Directory for temporary resources.
   -D --disable-hostonly                  Disable dracut's hostonly (default unset).
   -V --verbose                           Enable verbose mode and print errors out.
   -S --skip-cleanup                      Skip removal of mount/temp directory and do not unmount.
   -h --help                              Show this help.
_EOF
}

confirm() {
	cat <<_EOF
WARNING!
========
This will overwrite data on ${DISK} irrevocably.

	FLAVOR                     "${FLAVOR}"
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
	LINBOX_ROOT_PASSWORD       "${LINBOX_ROOT_PASSWORD}"
	LINBOX_USER                "${LINBOX_USER}"
	LINBOX_USER_PASSWORD       "${LINBOX_USER_PASSWORD}"
	LINBOX_LUKS_PASSWORD       "${LINBOX_LUKS_PASSWORD}"
	LINBOX_GRUB_USER           "${LINBOX_GRUB_USER}"
	LINBOX_GRUB_PASSWORD       "${LINBOX_GRUB_PASSWORD}"
	PHASES                     "${PHASES}"
	MOUNTPOINT                 "${MOUNTPOINT}"
	TMPDIR                     "${TMPDIR}"
	DISABLE_HOST_ONLY          "${DISABLE_HOST_ONLY}"
	VERBOSE                    "${VERBOSE}"
	SKIP_CLEANUP               "${SKIP_CLEANUP}"

Are you sure? (Type uppercase yes):
_EOF

	read -r answer
	if [ ! "${answer}" = "YES" ]; then
		die "Aborting due to user interaction..."
	fi
}

defaults() {
	: "${FLAVOR:="gentoo"}"
	: "${ARCH:="x86_64"}"
	: "${DISK:="/dev/sda"}"
	: "${BIOS_PART_SIZE:="2M"}"
	: "${EFI_PART_SIZE:="512M"}"
	: "${SWAP_PART_SIZE:="$(swapsize)G"}"
	: "${ROOT_PART_SIZE:="0"}"
	: "${HOSTNAME:="linbox"}"
	: "${LOCALE:="en_US.UTF-8"}"
	: "${KEYMAP:="de_CH-latin1"}"
	: "${XKB_LAYOUT:="ch"}"
	: "${XKB_VARIANT:="de_nodeadkeys"}"
	: "${XKB_OPTIONS:=""}"
	: "${TIMEZONE:="Europe/Zurich"}"
	: "${LINBOX_ROOT_PASSWORD:="$(genpasswd)"}"
	: "${LINBOX_USER:="user"}"
	: "${LINBOX_USER_PASSWORD:="${LINBOX_ROOT_PASSWORD}"}"
	: "${LINBOX_LUKS_PASSWORD:="${LINBOX_ROOT_PASSWORD}"}"
	: "${LINBOX_GRUB_USER:="${LINBOX_USER}"}"
	: "${LINBOX_GRUB_PASSWORD:="${LINBOX_ROOT_PASSWORD}"}"
	: "${PHASES:="wipefs partition encrypt mkfs btrfs preinstall install postinstall"}"
	: "${MOUNTPOINT:="/mnt/linbox"}"
	: "${TMPDIR:="$(mktemp --directory --suffix ".linbox" 2> /dev/null || printf '%s' '/tmp/linbox')"}"
	: "${DISABLE_HOST_ONLY:=""}"
	: "${SKIP_CLEANUP:=""}"
	: "${VERBOSE:=""}"
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
			-f|--flavor) param "FLAVOR" "${1}" "${2}" ;;
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
			-p|--password) param "LINBOX_ROOT_PASSWORD" "${1}" "${2}" ;;
			-u|--user) param "LINBOX_USER" "${1}" "${2}" ;;
			-U|--user-password) param "LINBOX_USER_PASSWORD" "${1}" "${2}" ;;
			-P|--luks-password) param "LINBOX_LUKS_PASSWORD" "${1}" "${2}" ;;
			-g|--grub-user) param "LINBOX_GRUB_USER" "${1}" "${2}" ;;
			-G|--grub-password) param "LINBOX_GRUB_PASSWORD" "${1}" "${2}" ;;
			-M|--mountpoint) param "MOUNTPOINT" "${1}" "${2}" ;;
			-T|--tmpdir) param "TMPDIR" "${1}" "${2}" ;;
			-Y|--phases) param "PHASES" "${1}" "${2}" ;;
			-D|--disable-hostonly) param "DISABLE_HOST_ONLY" "${1}" "yes" ;;
			-V|--verbose) param "VERBOSE" "${1}" "yes" ;;
			-S|--skip-cleanup) param "SKIP_CLEANUP" "${1}" "yes" ;;
		esac
		shift
	done

	unset -f param
}

out() {
	if [ ! "${SKIP_CLEANUP}" = "yes" ]; then
		umountsubvols "${MOUNTPOINT}"
		unmountpseudofs "${MOUNTPOINT}"
		closecrypt

		for dir in ${TMPDIR} ${MOUNTPOINT}; do
			rm -rf "${dir}"
		done
	fi
}

runphases() {
	[ "${VERBOSE}" = "yes" ] && to="" || to=" > /dev/null 2>&1"

	for phase in ${PHASES}; do
		log "Running phase: ${phase}"
		eval "phase_${phase}${to}"
	done
}

phase_wipefs() {
	info "Wiping disk ${DISK}"
	wipefs --all --force "${DISK}"
}

phase_partition() {
	info "Partitioning disk ${DISK}"

	sgdisk \
		--clear \
		--zap-all \
		--mbrtogpt \
		--new=1:0:+"${BIOS_PART_SIZE}" \
		--typecode=1:EF02 \
		--new=2:0:+"${EFI_PART_SIZE}" \
		--typecode=2:EF00 \
		--new=4:0:+"${SWAP_PART_SIZE}" \
		--typecode=4:8300 \
		--new=3:0:+"${ROOT_PART_SIZE}" \
		--typecode=3:8300 \
		"${DISK}"
}

phase_encrypt() {
	info "Creating LUKS keyfile"
	mkdir -p "${TMPDIR}"
	dd bs=512 count=4 iflag=fullblock status=none \
		if=/dev/urandom \
		of="${TMPDIR}/.crypt.key"
	chmod 000 "${TMPDIR}/.crypt.key"

	info "Formatting LUKS root & swap partitions ($(partitionpath 3), $(partitionpath 4))"
	# swap partition
	printf "%s" "${LINBOX_LUKS_PASSWORD}" | \
	cryptsetup \
		--batch-mode \
		--type luks1 \
		--cipher aes-xts-plain64 \
		--key-size 512 \
		--hash sha512 \
		--iter-time 100 \
		--use-random \
		luksFormat "$(partitionpath 4)" -

	# root partition
	printf "%s" "${LINBOX_LUKS_PASSWORD}" | \
	cryptsetup \
		--batch-mode \
		--type luks1 \
		--cipher aes-xts-plain64 \
		--key-size 512 \
		--hash sha512 \
		--iter-time 100 \
		--use-random \
		luksFormat "$(partitionpath 3)" -

	info "Adding LUKS keyfile to LUKS root & swap partitions ($(partitionpath 3), $(partitionpath 4))"
	# swap partition
	printf "%s" "${LINBOX_LUKS_PASSWORD}" | \
	cryptsetup \
		--iter-time 100 \
		luksAddKey "$(partitionpath 4)" \
		"${TMPDIR}/.crypt.key"

	# root partition
	printf "%s" "${LINBOX_LUKS_PASSWORD}" | \
	cryptsetup \
		--iter-time 100 \
		luksAddKey "$(partitionpath 3)" \
		"/${TMPDIR}/.crypt.key"
}

phase_mkfs() {
	opencrypt

	info "Creating MS-DOS filesystem for EFI partition ($(partitionpath 2))"
	mkfs.vfat -F 32 -n "EFI" "$(partitionpath 2)"

	info "Setting up swap area for swap partition (cryptswap)"
	mkswap \
		--label swap \
		"/dev/mapper/cryptswap"

	info "Creating BTRFS filesystem for root partition (cryptroot)"
	mkfs.btrfs \
		--force \
		--label root \
		"/dev/mapper/cryptroot"

	closecrypt
}

phase_btrfs() {
	opencrypt
	mountsubvol "/" "${MOUNTPOINT}"

	# live subvols
    info "Creating BTRFS live subvolumes"
	mkdir -p "${MOUNTPOINT}/subvols"
	for subvol in \
		@ \
		@boot \
		@home; do
		btrfs subvolume create "${MOUNTPOINT}/subvols/${subvol}"
	done

	# backup subvols
    info "Creating BTRFS snapshot subvolumes"
	mkdir -p "${MOUNTPOINT}/snaps"
	for subvol in \
		@ \
		@home; do
		btrfs subvolume create "${MOUNTPOINT}/snaps/${subvol}"
	done

	unmount "${MOUNTPOINT}"
	closecrypt
}

phase_preinstall() {
    if [ -f "lib/${FLAVOR}/preinstall.sh" ]; then
        . "lib/${FLAVOR}/preinstall.sh"
    fi
}

phase_install() {
    if [ -f "lib/${FLAVOR}/install.sh" ]; then
        . "lib/${FLAVOR}/install.sh"
    fi
}

phase_postinstall() {
    if [ -f "lib/${FLAVOR}/postinstall.sh" ]; then
        . "lib/${FLAVOR}/postinstall.sh"
    fi
}

main() {
	args "${@}"

	trap 'out' EXIT INT
	defaults
	confirm

	checkroot

	umountsubvols "${MOUNTPOINT}"
	unmountpseudofs "${MOUNTPOINT}"
	closecrypt

	runphases
}

main "${@}"
