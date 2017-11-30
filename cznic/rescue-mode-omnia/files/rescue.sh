#!/bin/sh
#
# Turris Omnia rescue script
# (C) 2016 CZ.NIC, z.s.p.o.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


DEBUG=1

DEV="/dev/mmcblk0"
FS_DEV="${DEV}p1"
FS_MOUNTPOINT="/mnt"
SRCFS_MOUNTPOINT="/srcmnt"
MEDKIT_FILENAME="omnia-medkit*.tar.gz"
FACTORY_SNAPNAME="@factory"

BIN_BTRFS="/usr/bin/btrfs"
BIN_MKFS="/usr/bin/mkfs.btrfs"
BIN_MOUNT="/bin/mount"
BIN_GREP="/bin/grep"
BIN_SED="/bin/sed"
BIN_UMOUNT="/bin/umount"
BIN_SYNC="/bin/sync"
BIN_AWK="/usr/bin/awk"
BIN_MV="/bin/mv"
BIN_DATE="/bin/date"
BIN_DD="/bin/dd"
BIN_FDISK="/usr/sbin/fdisk"
BIN_BLOCKDEV="/sbin/blockdev"
BIN_MKDIR="/bin/mkdir"
BIN_HWCLOCK="/sbin/hwclock"
BIN_SLEEP="/bin/sleep"
BIN_TAR="/bin/tar"
BIN_LS="/bin/ls"
BIN_SORT="/usr/bin/sort"
BIN_TAIL="/usr/bin/tail"
BIN_REBOOT="/sbin/reboot"
BIN_MDEV="`which mdev`"
[ -z "$BIN_MDEV" ] || BIN_MDEV="$BIN_MDEV -s"

d() {
	if [ $DEBUG -gt 0 ]; then
		echo "$@"
	fi
}

e() {
	echo "Error: $@" >&2
}

mount_fs() {
	d "mount_fs $1 $2"
	if ! [ -d $2 ]; then
		$BIN_MKDIR -p "$2"
	fi

	if $BIN_MOUNT | $BIN_GREP -E "on $2 ">/dev/null; then
		e "Mountpoint $2 already used. Exit."
		exit 21
	fi

	$BIN_MOUNT $1 $2
	if [ $? -ne 0 ]; then
		e "Mount $1 on $2 failed."
		return 22
	fi
}

umount_fs() {
	d "umount_fs $1"
	$BIN_UMOUNT $1
	if $BIN_MOUNT | $BIN_GREP -E "on $1 ">/dev/null; then
		$BIN_UMOUNT -fl $1
	fi
	if $BIN_MOUNT | $BIN_GREP -E "on $1 ">/dev/null; then
		$BIN_MOUNT -o remount,ro $1
	fi
	$BIN_SYNC
}

do_warning() {
	umount_fs $SRCFS_MOUNTPOINT
	while true; do
		rainbow all enable blue
		sleep 1
		rainbow all disable
		sleep 1
	done
}

do_panic() {
	umount_fs $SRCFS_MOUNTPOINT
	while true; do
		rainbow all enable red
		sleep 1
		rainbow all disable
		sleep 1
	done
}

reflash () {
	IMG=""
	# find image (give it 10 tries with 1 sec delay)
	for i in `seq 1 10`; do
		$BIN_MDEV
		for dev in `$BIN_AWK '$4 ~ /sd[a-z]+[0-9]?/ { print $4 }' /proc/partitions`; do
			d "Testing FS on device $dev"
			[ -b "/dev/$dev" ] || continue
			mount_fs "/dev/$dev" $SRCFS_MOUNTPOINT
			if [ $? -ne 0 ]; then
				continue
			fi
			d "Searching for ${SRCFS_MOUNTPOINT}/${MEDKIT_FILENAME} on $dev"
			IMG="$(ls -1d ${SRCFS_MOUNTPOINT}/to_flash | sort | tail -n 1)"
			if [ -n "${IMG}" ] && [ -d "${SRCFS_MOUNTPOINT}/to_flash" ]; then
				d "Found medkit file $IMG on device $dev"
				break
			else
				IMG=""
				d "Medkit file not found on device $dev"
				umount_fs $SRCFS_MOUNTPOINT
			fi
		done
		[ -z "${IMG}" ] || break
		sleep 1
	done

	if [ -n "${IMG}" ]; then
    if [ -r "${IMG}"/rootfs.img ]; then
		  if [ -r "${IMG}"/rootfs.img.md5 ]; then
				cd "${IMG}"
          md5sum -c rootfs.img.md5 || do_warning
				cd
      fi
      dd if="${IMG}"/rootfs.img of=$DEV bs=1M || do_warning
		fi
    if [ -r "${IMG}"/uboot.img ]; then
		  if [ -r "${IMG}"/uboot.img.md5 ]; then
				cd "${IMG}"
          md5sum -c uboot.img.md5 || do_warning
				cd
      fi
			mtd erase /dev/mtd0
			mtd write uboot.img /dev/mtd0 || do_warning
		fi
    if [ -r "${IMG}"/rescue.img ]; then
		  if [ -r "${IMG}"/rescue.img.md5 ]; then
				cd "${IMG}"
          md5sum -c rescue.img.md5 || do_warning
				cd
      fi
			mtd erase /dev/mtd1
			mtd write rescue.img /dev/mtd1 || do_warning
		fi
		umount_fs $SRCFS_MOUNTPOINT
    sync
	else
		d "No medkit image found. Please reboot."
		do_warning
	fi

	d "Reflash succeeded."
}


# main

reflash

rainbow all enable 0xffff00

while true; do
	sleep 10
done

exit 0

