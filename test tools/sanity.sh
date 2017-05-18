#!/bin/bash

TOPDIR=$(dirname $0)/..

. $TOPDIR/tests/cfg.sh
. $TOPDIR/tests/lib.sh

logf=${TESTLOG:-/tmp/dfs_test-`date +%s%N`}

init_test_env

declare -a all_tests

test_0() {
	echo "repo disks: ${repo_disks[@]}"
	echo "dfs disk: $DFS_DISK"
	echo "mntpnt: $DFS_MNTPNT"
	echo "mdpath: $MDPATH"
	# show repo info
	$DFS_CLI list -v | awk 'BEGIN {avail=0; disks=0; cntn=0}
		/Available blocks/ {avail += $3; cntn++}
		/Disk name/ { disks++}
		END { 
                   print "\tavailable blocks:", avail, 
                         "\n\tcontainers:", cntn, "\n\tdisks:", disks
                }'
	true
}
all_tests+=(test_0)

test_1() {
	rm -f $tfile # cleanup prior garbage if present 
	local count=$((RANDOM % 1024 + 100))
	dd if=/dev/urandom of=$tfile bs=1k count=$count ||
	error "dd failed"

	test_reg_file $tfile

	# $tfile should now be deduped
	tmpfile=$(mktemp)

	# testing direct read 
	echo "cp $tfile $tmpfile"
	cp $tfile $tmpfile

	# modify first 100k of tmpfile with some random data,
	# then modify the first 100k of tfile with that same data,
	# the result of two files should remain the same.
	dd if=/dev/urandom of=$tmpfile bs=1k count=100 conv=notrunc || 
	error "create failed"

	dd if=$tmpfile of=$tfile bs=1k count=100 conv=notrunc || 
	error "write failed"

	cmp $tmpfile $tfile || error "files differ after writing"

	rm -f $tmpfile
}
all_tests+=(test_1)

test_2() {
	testFileSet 1
	testFileSet 2
}
all_tests+=(test_2)

# This test inspects the repo's index file (along with delta files)
# to collect all entries that reference container data regions.
# These data regions are coalesced for each container and their signatures 
# are verified along with the contiguousness within the container, so that
# the used portion of the containers are all referenced.
#
test_3() {
	MDPATH=$MDPATH $REPO_INSPECT --verbose 1 || 
	error "repo inspection failed"
}
all_tests+=(test_3)

# This test inspects all files under the dfs dir tree and checks each file
# for the possibility of being a dfs stub file -- i.e., having a valid xattr.
# If so, original file content is computed based on the stub file entries
# and its checksum verified.
#
test_4() {
	MDPATH=$MDPATH $REPO_INSPECT --dirs $DFS_MNTPNT --verify --verbose 1 ||
	error "stub files inspection failed"
}
all_tests+=(test_4)

test_99() {
	touch $tfile
}
all_tests+=(test_99)

start_test() {
	start_dfs

	echo "running test"

	for tst in "${all_tests[@]}"; do
		echo "------ Start to run test '$tst' ------ "
		run_test $tst
		echo "------ Test '$tst' complete ------"
	done

	[ -z "$test_failed" ] && stop_dfs
}

cmd=$1
[ -z "$cmd" ] && cmd=test

case $cmd in
start)
	start_dfs ;;
stop)
	stop_dfs ;;
test)
	start_test 2>&1 | tee -a $logf
	;;
[0-9]*)
	run_test test_$cmd
	;;
*)
	echo "unknown command '$1'"
esac
