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

mkswapfile() {

}

genpasswd() {
	tr </dev/urandom -dc _A-Z-a-z-0-9 | head -c 16
}

partitionpath() {
	printf "%s" "$(sfdisk -l "${DISK}" | awk '/^\/dev/ {print $1}' | grep "${1}$")"
}

deviceuuid() {
	blkid -s UUID -o value "${1}"
}

opencrypt() {
	if ! cryptsetup status "crypt-$(deviceuuid "$(partitionpath 3)")" >/dev/null 2>&1; then
		cryptsetup \
			--key-file "${TMPDIR}/crypt/crypt.key" \
			luksOpen "$(partitionpath 3)" \
			"crypt-$(deviceuuid "$(partitionpath 3)")"
	fi
}

closecrypt() {
	if cryptsetup status "crypt-$(deviceuuid "$(partitionpath 3)")" >/dev/null 2>&1; then
		cryptsetup luksClose "crypt-$(deviceuuid "$(partitionpath 3)")" || :
	fi
}

mountsubvol() {
	mount_opts="compress=lzo,noatime,rw,space_cache,ssd,discard,subvol=${1}"

	mkdir -p "${2}"
	if ! mountpoint -q "${2}"; then
		mount \
			--types "btrfs" \
			--options "${mount_opts}" \
			"/dev/mapper/crypt-$(deviceuuid "$(partitionpath 3)")" \
			"${2}"
	fi
}

mountrootfs() {
	mountsubvol "/subvols/${1}/@" "${2}"
	mountsubvol "/subvols/${1}/@boot" "${2}/boot"
	mountsubvol "/subvols/@home" "${2}/home"

	if ! mountpoint -q "${2}/boot/efi"; then
		mkdir -p "${2}/boot/efi"
		mount "$(partitionpath 2)" "${2}/boot/efi"
	fi
}

unmountrootfs() {
	unmount "${1}/boot/efi"
	unmount "${1}/boot"
	unmount "${1}/home"
	unmount "${1}"
}

# mountpseudofs() {
# 	for f in sys dev proc run tmp; do
# 		if ! mountpoint -q "${1}/${f}"; then
# 			mkdir -p "${1}/${f}"
# 			mount --rbind "/${f}" "${1}/${f}"
# 			mount --make-rslave "${1}/${f}"
# 		fi
# 	done

# 	if ! mountpoint -q "${1}"/etc/resolv.conf; then
# 		mkdir -p "${1}/etc"
# 		touch "${1}/etc/resolv.conf"
# 		mount --bind "/etc/resolv.conf" "${1}/etc/resolv.conf"
# 	fi

# 	if [ -e /sys/firmware/efi/systab ] && ! mountpoint -q "${1}/sys/firmware/efi/efivars"; then
# 		mkdir p "${1}/sys/firmware/efi/efivars"
# 		mount -t efivarfs efivarfs "${1}/sys/firmware/efi/efivars"
# 	fi
# }

mountpseudofs() {
	for d in proc sys dev dev/pts dev/shm tmp run etc; do
		mkdir -p "${1}/${d}"
	done

	mountpoint -q "${1}/proc" || mount proc "${1}/proc" -t proc -o nosuid,noexec,nodev
	mountpoint -q "${1}/sys" || mount sys "${1}/sys" -t sysfs -o nosuid,noexec,nodev,ro
	mountpoint -q "${1}/dev" || mount udev "${1}/dev" -t devtmpfs -o mode=0755,nosuid
	mountpoint -q "${1}/dev/pts" || mount pts "${1}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
	mountpoint -q "${1}/dev/shm" || mount shm "${1}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
	mountpoint -q "${1}/tmp" || mount tmp "${1}/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid
	mountpoint -q "${1}/run" || mount /run "${1}/run" --bind

	if [ -e /sys/firmware/efi/systab ] && ! mountpoint -q "${1}/sys/firmware/efi/efivars"; then
		mount efivarfs "${1}/sys/firmware/efi/efivars" -t efivarfs -o nosuid,noexec,nodev
	fi

	if ! mountpoint -q "${1}/etc/resolv.conf"; then
		touch "${1}/etc/resolv.conf"
		mount "/etc/resolv.conf" "${1}/etc/resolv.conf" --bind
	fi
}

unmountpseudofs() {
	for d in \
		proc \
		etc/resolv.conf \
		sys/firmware/efi/efivars \
		sys \
		dev/pts \
		dev/shm \
		dev \
		tmp \
		run; do
		unmount "${1}/${d}"
	done
}

unmount() {
	if mountpoint -q "${1}"; then
		# umount "${1}" || umount -l "${1}" || :
		umount -f "${1}"
		sync
	fi
}

loopsetup() {
	dd if=/dev/zero of="${TMPDIR}/disk.img" bs=1G count=5 >/dev/null 2>&1
	DISK="$(losetup --show -fP "${TMPDIR}/disk.img")"
}

loopsetdown() {
	losetup -D
}

checkroot() {
	if [ "$(id -u)" -ne 0 ]; then
		die "Must be run as root, exiting..."
	fi
}

cmdchroot() {
	chroot "${MOUNTPOINT}" sh -c "${@}"
}

handleverbosity() {
	if [ "${VERBOSE}" = "yes" ]; then
		"${@}"
	else
		"${@}" >/dev/null 2>&1
	fi
}

copychroot() {
	find "${1}" -mindepth 1 -maxdepth 1 -exec \
		cp --recursive \
		--force \
		--preserve \
		--no-preserve ownership \
		-P \
		{} "${MOUNTPOINT}/${2}" \;
}

readpkgs() {
	pkgs=""
	while read -r pkg; do
		[ "${pkg##\#*}" ] || continue
		pkgs="${pkg} ${pkgs}"
	done <"lib/flavors/${1}/packages"
	printf "%s" "${pkgs}"
}

usage() {
	cat <<_EOF
Usage: linbox.sh [options]

Options:
   -f --flavors                           Set the distro flavor (gentoo, void, arch).
   -a --arch <arch>                       Set arch to use (x86_64 if unset).
   -d --disk <disk>                       Set disk to partition (/dev/sda if unset).
   -b --bios-part-size <bios-part-size>   Default bios partition size to use (2M if unset).
   -e --efi-part-size <efi-part-size>     Default efi partition size to use (512M if unset).
   -r --root-part--size <root-part-size>  Default root partition size to use (rest of space if unset).
   -s --swapfile-size <swapfile-size>     Default swapfile size to use (2x size of mem if unset).
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
   -S --skip-cleanup                      Skip removal of mount/temp directory and do not unmount.
   -V --verbose                           Enable verbose mode and print errors out.
   -L --loopback                          Use loopback instead of block device.
   -B --batchmode                         Skip user confirmations (batch mode).
   -h --help                              Show this help.
_EOF
}

confirm() {
	cat <<_EOF
WARNING!
========
This will overwrite data on ${DISK} irrevocably.

	FLAVORS                    "${FLAVORS}"
	ARCH                       "${ARCH}"
	DISK                       "${DISK}"
	BIOS_PART_SIZE             "${BIOS_PART_SIZE}"
	EFI_PART_SIZE              "${EFI_PART_SIZE}"
	ROOT_PART_SIZE             "${ROOT_PART_SIZE}"
	SWAPFILE_SIZE              "${SWAPFILE_SIZE}"
	HOSTNAME                   "${HOSTNAME}"
	LOCALE                     "${LOCALE}"
	KEYMAP                     "${KEYMAP}"
	XKB_LAYOUT                 "${XKB_LAYOUT}"
	XKB_VARIANT                "${XKB_VARIANT}"
	XKB_OPTIONS                "${XKB_OPTIONS}"
	TIMEZONE                   "${TIMEZONE}"
	ROOT_PASSWORD              "${ROOT_PASSWORD}"
	USER                       "${USER}"
	USER_PASSWORD              "${USER_PASSWORD}"
	LUKS_PASSWORD              "${LUKS_PASSWORD}"
	GRUB_USER                  "${GRUB_USER}"
	GRUB_PASSWORD              "${GRUB_PASSWORD}"
	PHASES                     "${PHASES}"
	MOUNTPOINT                 "${MOUNTPOINT}"
	TMPDIR                     "${TMPDIR}"
	DISABLE_HOST_ONLY          "${DISABLE_HOST_ONLY}"
	SKIP_CLEANUP               "${SKIP_CLEANUP}"
	VERBOSE                    "${VERBOSE}"
	LOOPBACK                   "${LOOPBACK}"
	BATCHMODE                  "${BATCHMODE}"

Are you sure? (Type uppercase yes):
_EOF

	if [ ! "${BATCHMODE}" = "yes" ]; then
		read -r answer
		if [ ! "${answer}" = "YES" ]; then
			die "Aborting due to user interaction..."
		fi
	fi
}

defaults() {
	: "${FLAVORS:="voidlinux"}"
	: "${ARCH:="x86_64"}"
	: "${DISK:="/dev/sda"}"
	: "${BIOS_PART_SIZE:="2M"}"
	: "${EFI_PART_SIZE:="512M"}"
	: "${SWAPFILE_SIZE:="$(swapsize)G"}"
	: "${ROOT_PART_SIZE:="0"}"
	: "${HOSTNAME:="linbox"}"
	: "${LOCALE:="en_US.UTF-8"}"
	: "${KEYMAP:="de_CH-latin1"}"
	: "${XKB_LAYOUT:="ch"}"
	: "${XKB_VARIANT:="de_nodeadkeys"}"
	: "${XKB_OPTIONS:=""}"
	: "${TIMEZONE:="Europe/Zurich"}"
	: "${ROOT_PASSWORD:="$(genpasswd)"}"
	: "${USER:="user"}"
	: "${USER_PASSWORD:="${ROOT_PASSWORD}"}"
	: "${LUKS_PASSWORD:="${ROOT_PASSWORD}"}"
	: "${GRUB_USER:="${USER}"}"
	: "${GRUB_PASSWORD:="${ROOT_PASSWORD}"}"
	: "${PHASES:="wipefs partition encrypt mkfs btrfs preinstall install postinstall"}"
	: "${MOUNTPOINT:="/mnt/linbox"}"
	: "${TMPDIR:="$(mktemp --directory --suffix ".linbox" 2>/dev/null || printf '%s' '/tmp/linbox')"}"
	: "${DISABLE_HOST_ONLY:=""}"
	: "${SKIP_CLEANUP:=""}"
	: "${VERBOSE:=""}"
	: "${LOOPBACK:=""}"
	: "${BATCHMODE:=""}"

	if [ "${LOOPBACK}" = "yes" ]; then
		log "Preparing loopback device"
		{
			loopsetup
		}
	fi
}

args() {
	unset HOSTNAME
	unset USER

	param() {
		if [ -n "${3}" ]; then
			eval "${1}=\"${3}\""
			shift
		else
			die "${2} requires a non-empty option argument"
		fi
	}

	while [ -n "${1}" ]; do
		case "${1}" in
		-h | --help)
			usage
			exit 0
			;;
		-f | --flavors) param "FLAVORS" "${1}" "${2}" ;;
		-a | --arch) param "ARCH" "${1}" "${2}" ;;
		-d | --disk) param "DISK" "${1}" "${2}" ;;
		-b | --bios-part-size) param "BIOS_PART_SIZE" "${1}" "${2}" ;;
		-e | --efi-part-size) param "EFI_PART_SIZE" "${1}" "${2}" ;;
		-s | --swapfile-size) param "SWAPFILE_SIZE" "${1}" "${2}" ;;
		-r | --root-part--size) param "ROOT_PART_SIZE" "${1}" "${2}" ;;
		-H | --hostname) param "HOSTNAME" "${1}" "${2}" ;;
		-l | --locale) param "LOCALE" "${1}" "${2}" ;;
		-k | --keymap) param "KEYMAP" "${1}" "${2}" ;;
		-x | --xkb-layout) param "XKB_LAYOUT" "${1}" "${2}" ;;
		-X | --xkb-variant) param "XKB_VARIANT" "${1}" "${2}" ;;
		-Z | --xkb-options) param "XKB_OPTIONS" "${1}" "${2}" ;;
		-t | --timezone) param "TIMEZONE" "${1}" "${2}" ;;
		-p | --password) param "ROOT_PASSWORD" "${1}" "${2}" ;;
		-u | --user) param "USER" "${1}" "${2}" ;;
		-U | --user-password) param "USER_PASSWORD" "${1}" "${2}" ;;
		-P | --luks-password) param "LUKS_PASSWORD" "${1}" "${2}" ;;
		-g | --grub-user) param "GRUB_USER" "${1}" "${2}" ;;
		-G | --grub-password) param "GRUB_PASSWORD" "${1}" "${2}" ;;
		-M | --mountpoint) param "MOUNTPOINT" "${1}" "${2}" ;;
		-T | --tmpdir) param "TMPDIR" "${1}" "${2}" ;;
		-Y | --phases) param "PHASES" "${1}" "${2}" ;;
		-D | --disable-hostonly) param "DISABLE_HOST_ONLY" "${1}" "yes" ;;
		-S | --skip-cleanup) param "SKIP_CLEANUP" "${1}" "yes" ;;
		-V | --verbose) param "VERBOSE" "${1}" "yes" ;;
		-L | --loopback) param "LOOPBACK" "${1}" "yes" ;;
		-B | --batchmode) param "BATCHMODE" "${1}" "yes" ;;
		esac
		shift
	done

	unset -f param
}

out() {
	if [ "${LOOPBACK}" = "yes" ]; then
		loopsetdown
	fi

	if [ ! "${SKIP_CLEANUP}" = "yes" ]; then
		unmountpseudofs "${MOUNTPOINT}"
		unmountrootfs "${MOUNTPOINT}"
		closecrypt

		for dir in ${TMPDIR} ${MOUNTPOINT}; do
			rm -rf "${dir}"
		done
	fi
}

runphases() {
	[ "${VERBOSE}" = "yes" ] && to="" || to=" >/dev/null 2>&1"

	for phase in ${PHASES}; do
		log "Running phase: ${phase}"
		{
			eval "phase_${phase}${to}"
		}
	done
}

phase_wipefs() {
	info "Wiping disk ${DISK}"
	{
		wipefs --all --force "${DISK}"
	} >/dev/null 2>&1
}

phase_partition() {
	info "Partitioning disk ${DISK}"
	{
		sgdisk \
			--clear \
			--zap-all \
			--mbrtogpt \
			--new=1:0:+"${BIOS_PART_SIZE}" \
			--typecode=1:EF02 \
			--new=2:0:+"${EFI_PART_SIZE}" \
			--typecode=2:EF00 \
			--new=3:0:+"${ROOT_PART_SIZE}" \
			--typecode=3:8300 \
			"${DISK}"
	} >/dev/null 2>&1
}

phase_encrypt() {
	info "Creating LUKS keyfile"
	{
		mkdir -p "${TMPDIR}/crypt"
		dd bs=512 count=4 iflag=fullblock status=none \
			if=/dev/urandom \
			of="${TMPDIR}/crypt/crypt.key"
		chmod 000 "${TMPDIR}/crypt/crypt.key"
	} >/dev/null 2>&1

	info "Formatting LUKS root partition ($(partitionpath 3))"
	{
		printf "%s" "${LUKS_PASSWORD}" |
			cryptsetup \
				--batch-mode \
				--type luks1 \
				--cipher aes-xts-plain64 \
				--key-size 512 \
				--hash sha512 \
				--iter-time 100 \
				--use-random \
				luksFormat "$(partitionpath 3)" -
	} >/dev/null 2>&1

	info "Adding LUKS keyfile to LUKS root partition ($(partitionpath 3))"
	{
		printf "%s" "${LUKS_PASSWORD}" |
			cryptsetup \
				--iter-time 100 \
				luksAddKey "$(partitionpath 3)" \
				"/${TMPDIR}/crypt/crypt.key"
	} >/dev/null 2>&1
}

phase_mkfs() {
	opencrypt

	info "Creating MS-DOS filesystem for EFI partition ($(partitionpath 2))"
	{
		mkfs.vfat -F 32 -n "EFI" "$(partitionpath 2)"
	} >/dev/null 2>&1

	info "Creating BTRFS filesystem for root partition (crypt-$(deviceuuid "$(partitionpath 3)"))"
	{
		mkfs.btrfs \
			--force \
			--label root \
			"/dev/mapper/crypt-$(deviceuuid "$(partitionpath 3)")"
	} >/dev/null 2>&1

	closecrypt
}

phase_btrfs() {
	opencrypt
	mountsubvol "/" "${MOUNTPOINT}"

	info "Creating shared distro BTRFS live subvolumes"
	{
		mkdir -p "${MOUNTPOINT}/subvols"
		for subvol in \
			@swap \
			@home; do
			btrfs subvolume create "${MOUNTPOINT}/subvols/${subvol}"
		done
	} >/dev/null 2>&1

	info "Preparing swapfile"
	{
		truncate -s 0 "${MOUNTPOINT}/subvols/@swap/swapfile"
		chattr +C "${MOUNTPOINT}/subvols/@swap/swapfile"
		btrfs property set "${MOUNTPOINT}/subvols/@swap/swapfile"
		fallocate -l "${SWAPFILE_SIZE}" "${MOUNTPOINT}/subvols/@swap/swapfile"
		chmod 600 "${MOUNTPOINT}/subvols/@swap/swapfile"
		mkswap "${MOUNTPOINT}/subvols/@swap/swapfile"
		swapon "${MOUNTPOINT}/subvols/@swap/swapfile"

		# TODO: make function to calculate offset
		# See: https://endeavouros.com/docs/encrypted-installation-2/btrfsonluks-quick-copypaste-version/
		offset=$(lib/common/files/usr/bin/btrfs_map_physical "${MOUNTPOINT}/subvols/@swap/swapfile")
		offset_arr=($(echo ${offset}))
		offset_pagesize=($(getconf PAGESIZE))
		offset=$((offset_arr[25] / offset_pagesize))
	} >/dev/null 2>&1

	info "Creating distro specific BTRFS live subvolumes"
	{
		for flavor in ${FLAVORS}; do
			mkdir -p "${MOUNTPOINT}/subvols/${flavor}"
			for subvol in \
				@; do
				btrfs subvolume create "${MOUNTPOINT}/subvols/${flavor}/${subvol}"
			done
		done
	} >/dev/null 2>&1

	info "Creating shared distro BTRFS snapshot subvolumes"
	{
		mkdir -p "${MOUNTPOINT}/snaps"
		for subvol in \
			@home; do
			btrfs subvolume create "${MOUNTPOINT}/snaps/${subvol}"
		done
	} >/dev/null 2>&1

	info "Creating distro specific BTRFS snapshot subvolumes"
	{
		for flavor in ${FLAVORS}; do
			mkdir -p "${MOUNTPOINT}/snaps/${flavor}"
			for subvol in \
				@; do
				btrfs subvolume create "${MOUNTPOINT}/snaps/${flavor}/${subvol}"
			done
		done
	} >/dev/null 2>&1

	unmount "${MOUNTPOINT}"
	closecrypt
}

phase_preinstall() {
	for flavor in ${FLAVORS}; do
		if [ -f "lib/flavors/${flavor}/preinstall.sh" ]; then
			info "Flavor '${flavor}'"
			{
				# Can't follow non-constant source. Use a directive to specify location.
				# shellcheck disable=SC1090
				. "lib/flavors/${flavor}/preinstall.sh"
			}
		fi
	done
}

phase_install() {
	for flavor in ${FLAVORS}; do
		if [ -f "lib/flavors/${flavor}/install.sh" ]; then
			info "Flavor '${flavor}'"
			{
				# Can't follow non-constant source. Use a directive to specify location.
				# shellcheck disable=SC1090
				. "lib/flavors/${flavor}/install.sh"
			}
		fi
	done
}

phase_postinstall() {
	for flavor in ${FLAVORS}; do
		if [ -f "lib/flavors/${flavor}/postinstall.sh" ]; then
			info "Flavor '${flavor}'"
			{
				# Can't follow non-constant source. Use a directive to specify location.
				# shellcheck disable=SC1090
				. "lib/flavors/${flavor}/postinstall.sh"
			}
		fi
	done
}

# needed for development
phase_mount() {
	opencrypt
	for flavor in ${FLAVORS}; do
		mountrootfs "${flavor}" "${MOUNTPOINT}/${flavor}"
		mountpseudofs "${MOUNTPOINT}/${flavor}"
	done
}

# needed for development
phase_unmount() {
	for flavor in ${FLAVORS}; do
		unmountpseudofs "${MOUNTPOINT}/${flavor}"
		unmountrootfs "${MOUNTPOINT}/${flavor}"
	done
	closecrypt
}

main() {
	args "${@}"

	trap 'out' EXIT INT

	defaults
	checkroot
	confirm

	# needed if mounting and unmounting is required due to development
	if [ ! "${PHASES}" = "mount" ] && [ ! "${PHASES}" = "unmount" ]; then
		unmountpseudofs "${MOUNTPOINT}"
		unmountrootfs "${MOUNTPOINT}"
		closecrypt
	fi

	runphases

	log "Flavors '${FLAVORS}' successfully installed"
}

main "${@}"
