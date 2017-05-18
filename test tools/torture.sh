#!/bin/bash

TOPDIR=$(dirname $0)/..

. $TOPDIR/tests/cfg.sh
. $TOPDIR/tests/lib.sh

declare -a all_tortures

# utility program to read and write files
FSX=$(which fsx 2> /dev/null)
FSXcheck=$($(which fsx 2> /dev/null) | echo $?)

init_test_env

check_partition_usage(){
	local left_space=$(df | grep /mnt/dfs | awk '{print $4}')
	[ "$left_space" = 0 ] && error "partition is full"
}

torture_6() {
	# ask dfsd to shutdown
	echo "$DFS_CLI ctrl stop"
	$DFS_CLI ctrl stop

	MDPATH=$MDPATH $REPO_INSPECT --verify --verbose 1 || error "repo inspection failed"
	start_dfs # restart dfs

	# set logLevel to 2
	echo "$DFS_CLI ctrl log 2"
	$DFS_CLI ctrl log 2

	# set test fail location to 8 (rpxCommitEntry) with 4 times to failure
	echo "$DFS_CLI test_set 8 4"
	$DFS_CLI test_set 8 4 

	error_okay=true
	echo "set error_okay=$error_okay"

	echo "testFileSet 2"
	testFileSet 2

	REFORMAT=""
	start_dfs

	error_okay=""
	echo "set error_okay=$error_okay"
	echo "testFileSet 2"
	testFileSet 2
}
all_tortures+=(torture_6)

#fsx test with a random file in dfs partition
torture_7() {
	[[ $FSXcheck -eq 1 ]] && echo "fsx not installed, skip this test" &&
	return
	rm -f $tfile*
	echo "Running fsx..."
	$FSX -q -N 20000 $tfile || error "fsx failed"
}
all_tortures+=(torture_7)

#fsx test with a deduped random file
torture_8() {
	[[ $FSXcheck -eq 1 ]] && echo "fsx not installed, skip this test" &&
	return
	rm -f $tfile*
	echo "Creating random file....."
	dd if=/dev/urandom of=$tfile bs=1K count=$((RANDOM % 1024 +100 )) ||
		error "dd failed"

	echo "Dedup file..."
	$DFS_CLI dedup $tfile || error "dedup failed"
	#make sure file is deduped
	$DFS_CLI check $tfile | grep -q 'deduped' || error "not deduped"
	echo "running fsx..."
	$FSX -q -W -R -N 200000 $tfile && error "fsx running on a deduped file" ||
		echo "Cannot run fsx on a deduped file, test passed"
}
all_tortures+=(torture_8)

#check if a file larger than partition size could be generated
torture_9() {
	rm -f $tfile
	echo "Generating a file larger than partition size...."
	dd if=/dev/zero of=$tfile bs=1k count=$(($(stat -f -c%b $DFS_MNTPNT)+100)) &&
		error "a file larger than partition size is copied" || echo "Disk is full, test passed"
	rm -f $tfile
}
all_tortures+=(torture_9)

#Dedup a directory and restore test, and submit many dedup and restore requests to dfs_cli at the same time
torture_10(){
	local tdir=$DFS_MNTPNT/testdir
	rm -rf $tdir
	mkdir $tdir

	#generate random files
	local count=$((RANDOM % 100 + 100))
	echo "Generating random files..."
	for ((i=0;i<count;i++)); do
	{
		dd if=/dev/urandom of=$tdir/file$i bs=$((RANDOM % 1024 + 100)) \
		count=$((RANDOM % 200 + 100))  >& /dev/null || error "dd failed"
	}
	done
	echo "$count files created"

	echo "Dedup the directory..."
	$DFS_CLI Dedup $tdir
	echo "Check file and restore..."
	for ((i=0;i<count;i++)); do
	{
		$DFS_CLI restore $tdir/file$i || error "file$i restore failed"
	} &
	done
	wait

	echo "Submit massive dedup requests via dfs_cli..."
	for ((i=0;i<count;i++)); do
	{
		test_reg_file $tdir/file$i
	} &
	done
	process=`ps aux | grep $DFS_CLI | grep -v grep | awk '{print $1}' | wc -l`
	echo "$process dedup requests submitted at the same time"
	wait

	echo "Submit massive restore requests via dfs_cli..."
	for ((i=0;i<count;i++)); do
	{
		$DFS_CLI restore $tdir/file$i || error "file$i restore failed"
	} &
	done
	process=`ps aux | grep $DFS_CLI | grep -v grep | awk '{print $1}' | wc -l`
	wait
	echo "$process restore requests submitted at the same time"
}
all_tortures+=(torture_10)

#this test is to check dedup will split 1MB chunk correctly
torture_11(){
	rm -f $tfile*
	local before=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 | grep cInfo |
		awk '{sum +=$4};END {print sum}')
	local countno=$((RANDOM % 5 + 3))

	echo "Generating 2 files, both size are $countno MB, \
first $(($countno-2))MB of them have the same contents"
	echo "$before blocks are used before dedup"

	dd if=/dev/urandom of=$tfile.1 bs=1M count=$countno >& /dev/null || error "dd failed"
	dd if=/dev/urandom of=$tfile.2 bs=1M count=$countno >& /dev/null || error "dd failed"
	dd if=$tfile.1 of=$tfile.2 bs=1M count=$(($countno-2)) conv=notrunc >& /dev/null ||
		error "dd failed"

	$DFS_CLI dedup $tfile.1
	$DFS_CLI dedup $tfile.2

	local after=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 | grep cInfo |
		awk '{sum +=$4};END {print sum}')
	echo "$after blocks are used after dedup"
	[[ $(($after - $before )) -eq $(($countno * 2 * 1024 / 4 - $(($countno - 2)) * 1024 / 4 )) ]] &&
		echo "test passed, files are split into 1MB chunks correctly." ||
		error "test failed"
}
all_tortures+=(torture_11)

#container boundary test
torture_12(){
	rm -f $tfile
	local blocks=$(($DISKSIZE * 1024 / 4 / 8 - 1))

	echo "Generating a file which size is the same as container"
	dd if=/dev/urandom of=$tfile bs=4k count=$blocks || error "dd failed"

	echo "Dedup this file and check the cksum"
	$DFS_CLI dedup $tfile || error "dedup failed"
	cksum $tfile && echo "container boundary test passed" || error "test failed"
}
all_tortures+=(torture_12)

#test a special file which cannot be deduped
torture_13(){
	# make sure container is empty
	REFORMAT="yes"

	# ask dfsd to shutdown
	echo "$DFS_CLI ctrl stop"
	$DFS_CLI ctrl stop

	start_dfs # restart dfs
	REFORMAT="no"

	raw="$TOPDIR/tests/raw"
	tstDir="$DFS_MNTPNT/testData"
	fSet="$tstDir/set1"
	rm -rf $fSet # cleanup prior garbage if present
	$genFileSet 1 $raw $tstDir

	#generate bug file
	echo "Generating bug file..."
	dd if=$fSet/tf2 of=$tfile bs=1M count=20 || error "dd failed"
	$DFS_CLI dedup $tfile && echo "test passed" || error "dedup failed"
}
all_tortures+=(torture_13)

run_torture() {
    torture=$1
    echo "------ Starting '$torture' ------"
    run_test $torture
    echo "------ '$torture' complete ------"
}

run_all_tortures() {
	start_dfs

	echo "start torture tests"

	for torture in "${all_tortures[@]}"; do
	    run_torture $torture
	done

	[ -z "$test_failed" ] && stop_dfs
}


cmd=$1
[ -z "$cmd" ] && cmd=all

case $cmd in
start)
	start_dfs ;;
stop)
	stop_dfs;;
all)
	run_all_tortures ;;
[1-9]*)
	run_torture torture_$cmd
	;;
*)
	echo "unknown command '$1'"
esac
