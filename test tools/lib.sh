#!/bin/bash

TOPDIR=$(dirname $0)/..
MODIR=$TOPDIR/module
DFSD=$TOPDIR/daemon/dfsd/dfsd
DFS_CLI=$TOPDIR/cmd/dfs_cli
REPO_INSPECT=$TOPDIR/tests/src/inspect

# utility program to generate test files
genFileSet=$TOPDIR/tests/src/genFileSet

. $TOPDIR/tests/cfg.sh

declare test_failed

error() {
	echo "$1"

	test_failed=yes
	while caller $i; do
		i=$((i+1))
	done
	[ -z "$error_okay" ] && exit 1
}

load_modules() {
	lsmod | grep -q dfs || insmod $MODIR/dfs.ko || error "module install"
}

unload_modules() {
	rmmod dfs &> /dev/null || true
}

start_daemon() {
	local name=$(basename $DFSD)
	pgrep $name &> /dev/null || {
		echo "exec MDPATH=$MDPATH $DFSD"
		MDPATH=$MDPATH $DFSD
		pgrep $name &> /dev/null || error "start daemon failed"
	}
}

stop_daemon() {
	pkill $(basename $DFSD)
}

declare -a repo_disks

init_disk_names() {
	local idx

	for ((idx = 0; idx < DISKCOUNT; idx++)); do
		local ptr=DISK$idx
		repo_disks+=(${!ptr})
	done
}

format_repo() {
	declare -a disks

	stop_daemon
	unload_modules

	rm -rf $MDPATH/DISKS/* $MDPATH/repo/* $MDPATH/last_container_index
	mkdir -p $MDPATH/DISKS $MDPATH/repo

	for ((idx = 0; idx < DISKCOUNT; idx++)); do
		local disk=${repo_disks[$idx]}

		[ -z "$disk" ] && error "DISK$idx is not indicated"
		[ -b "$disk" ] && {
			disks+=($disk)
			continue
		}

		[ -e $disk -a ! -f $disk ] &&
		error "$disk is not a regular file"

		rm -f $disk
		dd if=/dev/zero of=$disk bs=1M count=1 seek=$((DISKSIZE-1)) \
		    &> /dev/null ||
			error "creating repo disk $disk failed"

		local dev=$(losetup -f)
		losetup $dev $disk
		disks+=($dev)
	done

	[ ! -e $disk -o -f $disk -o -b $disk ] ||
		error "$disk is not a regular file or block device"

	[ -f $DFS_DISK -o ! -e $DFS_DISK ] && {
		rm -f $DFS_DISK
		dd if=/dev/zero of=$DFS_DISK bs=1M count=1 \
		    seek=$((DFS_DISKSIZE-1)) &> /dev/null ||
			error "creating dfs disk $DFS_DISK failed"
	}

	mkfs.ext4 -F $DFS_DISK > /dev/null

	load_modules
	echo "wait a little ..."; sleep 1;
	start_daemon

	for ((idx = 0; idx < DISKCOUNT; idx++)); do
		$DFS_CLI add -f ${disks[$idx]}
	done
}

start_dfs() {
	[ ! -e $MDPATH/DISKS -o ! -e $MDPATH/repo ] && REFORMAT=yes

	if [ "$REFORMAT" = "yes" ]; then
		stop_dfs
		format_repo
	else
		for ((idx = 0; idx < DISKCOUNT; idx++)); do
			local dsk=${repo_disks[$idx]}

			[ -z "$dsk" ] && error "DISK$idx is not indicated"
			[ ! -e $dsk ] && error "DISK$idx: $dsk not exist"
			[ -b $dsk ] && continue

			[ ! -f $dsk ] &&
			error "DISK$idx: $dsk is not a regular file"

			local dev=$(losetup -f)
			losetup $dev $dsk
		done

		load_modules
		start_daemon
	fi

	if grep -q $DFS_MNTPNT /proc/mounts; then
		# check if it has already mounted to $DFS_DISK
		local dev=$(mount | grep $DFS_MNTPNT | awk '{print $1}')
		[ "$dev" = "$DFS_DISK" ] || error "$DFS_MNTPNT mounted to $dev"
	else
		local opt

		mkdir -p $DFS_MNTPNT
		[ -f $DFS_DISK ] && opt="-oloop"
		mount -t dfs $opt $DFS_DISK $DFS_MNTPNT ||
		error "mount $DFS_DISK error"
	fi
}

stop_dfs() {
	echo "stop_dfs"
	local dev

	umount $DFS_MNTPNT &> /dev/null
	stop_daemon
	unload_modules

	for dsk in "${repo_disks[@]}"; do
		dev=$(losetup -l | grep $dsk | awk '{ print $1 }')
		[ -z "$dev" ] || losetup -d $dev
	done

	dev=$(losetup -l | grep $DFS_DISK | awk '{ print $1 }')
	[ -z "$dev" ] || losetup -d $dev
}

init_test_env() {
	init_disk_names
}

run_test() {
	local testname=$1
	export tfile=$DFS_MNTPNT/f${testname}

	# tfile may be created and left regardless of error
	rm -f $tfile # cleanup prior garbage if present

	$testname || error "run test '$testname' failed"

	# Don't cleanup this file so that other tests may use it
#	[ -z "$test_failed" ] && rm -f $tfile
}

test_reg_file() {
	regFile=$1
	echo "Testing reg file:$regFile"
	local cksum=$(md5sum $regFile | awk '{print $1}')
	local blocks=$(stat --format=%b $regFile)

	$DFS_CLI dedup $regFile

	# make sure dedup is succeeded
	$DFS_CLI check $regFile | grep -q 'deduped' || error "$regFile not deduped"

	# check direct read
	echo 3 > /proc/sys/vm/drop_caches
	local new_cksum=$(md5sum $regFile | awk '{print $1}')
	local new_blocks=$(stat --format=%b $regFile)

	echo "Checking deduped $regFile checksum and blocks"
	[ "$cksum" = "$new_cksum" ] ||
		error "cksum mismatch: $cksum vs. $new_cksum"
	[ "$blocks" -gt "$new_blocks" ] ||
		error "blocks: $blocks vs. $new_blocks"
	echo "Verifying deduped $regFile"
	MDPATH=$MDPATH $DFS_CLI verify $regFile || error "verification failed"
	echo "Verification of deduped $regFile done"
}

testFileSet() {
	fSetNumber=$1
	raw="$TOPDIR/tests/raw"
	tstDir="$DFS_MNTPNT/testData"
	fSet="$tstDir/set${fSetNumber}"
	rm -rf $fSet # cleanup prior garbage if present
	echo "$genFileSet $fSetNumber $raw $tstDir"
	$genFileSet $fSetNumber $raw $tstDir
	for tstfile in `ls $fSet`; do
	    echo "file: $tstfile"
	    tfile=$fSet/$tstfile
	    test_reg_file $tfile
	done
}
