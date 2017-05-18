#!/bin/bash

TOPDIR=$(dirname $0)/..

. $TOPDIR/tests/cfg.sh
. $TOPDIR/tests/lib.sh

TESTDIR=$DFS_MNTPNT/testData/set66
[ -e $TESTDIR ] || mkdir -p $TESTDIR

name=$(basename $DFSD)
# declare a flag when dfsd is down by pkill or fail location
declare STOPPED=""
# declare a flag when dedup/restore is failed
declare DEDUP_FAILED=""
declare RESTORE_FAILED=""
declare md5sum

init_test_env

# override error() in lib.sh to stop dfsd after error
# avoid create_error() is still running background
error() {
	echo "$1"

	test_failed=yes
	while caller $i; do
		i=$((i+1))
	done
	$DFS_CLI ctrl stop
	[ -z "$error_okay" ] && exit 1
}

# set fail location or kill dfsd at a random time
create_error() {
	#every 10-40 seconds
	local -i stoptime=$(( ( RANDOM % 31 )  + 10 ))

	# roll a dice from 0 to 13
	# if the number is 0, 5, 6, just kill dfsd
	# if other number, set the fail location
	while sleep $stoptime & wait; do
		# if SIGINT or SIGTERM are captured, jump out of the loop
		trap break SIGINT SIGTERM

		# if dfsd is not started, start dfsd first
		pgrep $name &> /dev/null || start_dfs

		local -i dice=$(( RANDOM % 14 ))
		[ $dice = "0" -o $dice = "5" -o $dice = "6" ] && {
			echo "pkill -9 dfsd"
			pkill -9 $name
		}
		[ $dice -gt "0" ] && [ $dice -ne "5" ] && [ $dice -ne "6" ] && {
			echo "set QA fail location $dice"
			$DFS_CLI test_set $dice 0
		}
		
		# if dfsd exits, mark STOPPED as yes
		pgrep $name &> /dev/null || {
			echo "dfsd is stopped"
			STOPPED=yes
		}
	done &
}

gen_random_files() {
	local fileNumber=$1
	local -i dice=$(( RANDOM % 2 ))
	# dice will be 0 and 1 randomly
	# if dice=0, generate data from /dev/urandom
	[ $dice = "0" ] && {
		local -i size=$(( ( RANDOM % 31 )  + 10 ))
		echo "generate files by dd, size $size MB"
		dd if=/dev/urandom of=$TESTDIR/tf$fileNumber bs=1M count=$size ||
		 error "dd failed"
	}

	# if dice=1, generate data from genFileSet
	# with random suffix and random size
	[ $dice = "1" ] && {
		local raw="$TOPDIR/tests/raw"
		local tstDir="$DFS_MNTPNT/testData"
		local suffix=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 3 | head -n 1)
		echo "generate files by genFileSet ,suffix is $suffix"
		$genFileSet 66 $raw $tstDir $suffix $fileNumber
	}
}

dedup_file() {
	local fileNumber=$1
	md5sum=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')
	echo "Deduping file: tf$fileNumber"
	$DFS_CLI dedup $TESTDIR/tf$fileNumber || DEDUP_FAILED=yes
}

restore_file() {
	local fileNumber=$1
	md5sum=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')
	echo "Restoring file: tf$fileNumber"
	$DFS_CLI restore $TESTDIR/tf$fileNumber || RESTORE_FAILED=yes
}

verify_file() {
	local fileNumber=$1
	# get the output of "nStubs" from inspect
	local nStubs=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber | awk -F ':' '{print $2}' | tail -n 1 | tr -dc '0-9')
	# get the output of "nFiles" from inspect
	local nFiles=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber | awk -F ':' '{print $3}' | tail -n 1 | tr -dc '0-9')

	# if dfsd is running, dedup/restore failed
	# it will be a critical error
	[ -z "$STOPPED" ] &&
	 [ "$DEDUP_FAILED" = "yes" -o "$RESTORE_FAILED" = "yes" ] && {
		error "dfsd is still running, but dedup/restore failed"
		# do some more check
	}

	# if dfsd is down, but dedup/restore is not failed
	# do regular check
	[ "$STOPPED" = "yes" ] &&
	 [ -z "$DEDUP_FAILED" ] && [ -z $RESTORE_FAILED ] && {
		 STOPPED=""
		 start_dfs
		 verify_file $fileNumber
	}

	# if dfsd is down and dedup/restore is failed
	[ "$STOPPED" = "yes" ] &&
	 [ "$DEDUP_FAILED" = "yes" -o "$RESTORE_FAILED" = "yes" ] && {

		 STOPPED=""
		 DEDUP_FAILED=""
		 RESTORE_FAILED=""
	 }

	# if dfsd is running and dedup/restore succeed
	[ -z "$STOPPED" ] && [ -z "$DEDUP_FAILED" ] && [ -z $RESTORE_FAILED ] && {
		local new_md5sum=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')
		$DFS_CLI check $TESTDIR/tf$fileNumber | grep -q 'deduped' ||
		 error "tf$fileNumber not deduped"
		echo "Checking md5sum of tf$fileNumber"
		[ "$md5sum" = "$new_md5sum" ] ||
			error "md5sum mismatch: $md5sum vs. $new_md5sum"

		echo "Inspecting tf$fileNumber"
		MDPATH=$MDPATH $REPO_INSPECT --verbose 2 --verify \
		--dir $TESTDIR/tf$fileNumber || error "inspect failed"
		echo "Inspect of tf$fileNumber done"
	}
}

gen_random_files 1
dedup_file 1
verify_file 1
