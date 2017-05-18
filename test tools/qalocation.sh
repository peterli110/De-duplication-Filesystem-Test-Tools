#!/bin/bash

TOPDIR=$(dirname $0)/..

. $TOPDIR/tests/cfg.sh
. $TOPDIR/tests/lib.sh

declare -a all_qalocations

name=$(basename $DFSD)

init_test_env

# override start_daemon() in lib.sh
# sleep 0.5 second to waiting for
# dfsd started and exited at the fail location.
start_daemon() {
	local name=$(basename $DFSD)
	pgrep $name &> /dev/null || {
		echo "exec MDPATH=$MDPATH $DFSD"
		MDPATH=$MDPATH $DFSD
		sleep 0.5
		pgrep $name &> /dev/null || error "start daemon failed"
	}
}

# this function is to test the QA fail location
# which is listed in include/qa.h
# usage: qa_test arg1 arg2 arg3
# arg1: QA fail location, from 0 to 14
# arg2: count, dfsd will exit after (arg2+1) times. Default: 0
# arg3: if arg3 is not null, dfs will not reformat at beginning
qa_test() {
	local -i count

	error_okay=true
	echo "set error_okay=$error_okay"

	[ -n $2 ] && count=$2 || count=0
	[ -z $3 ] && REFORMAT="yes"
	start_dfs # restart dfs
	REFORMAT=""

	# set logLevel to 2
	echo "$DFS_CLI ctrl log 2"
	$DFS_CLI ctrl log 2
	# set test fail location to $1 with 1 time to failure
	echo "$DFS_CLI test_set $1 $count"
	$DFS_CLI test_set $1 $count

	# fail location 5(rpxLoadBucketMeta) doesn't need any files
	if [ "$1" != "5" ]; then
		echo "testFileSet 3"
		testFileSet 3 > /dev/null # we only need stderr
	fi

	# fail location 5(rpxLoadBucketMeta) and 6(rpxReplayDelta)
	# could only be triggered by a cfg file
	# under $MDPATH/repo/cfg
	if [ "$1" = "5" -o "$1" = "6" ]; then
		echo "test_set $1 0" > $MDPATH/repo/cfg
		echo "$DFS_CLI ctrl stop"
		$DFS_CLI ctrl stop
		start_dfs
	fi

	# fail location 14(rpxFlushCache) need to
	# dedup some data first, and then flush
	if [ "$1" = "14" ]; then
		echo "Flushing cache..."
		$DFS_CLI ctrl flush
	fi

	error_okay=""
	echo "set error_okay=$error_okay"

	pgrep $name &> /dev/null && error "fail location is not triggered"
	[ -e "$MDPATH/repo/cfg" ] && rm -f $MDPATH/repo/cfg

	start_dfs
}

qalocation_1() {
	echo "rpxSplitBucket test"
	qa_test 1
}
all_qalocations+=(qalocation_1)

qalocation_2() {
	echo "rpxMigrate test"
	qa_test 2
}
all_qalocations+=(qalocation_2)

qalocation_3() {
	echo "rpxExtendChain test"
	qa_test 3
}
all_qalocations+=(qalocation_3)

qalocation_4() {
	echo "rpxSaveBucketMeta test"
	qa_test 4
}
all_qalocations+=(qalocation_4)

qalocation_5() {
	echo "rpxLoadBucketMeta test"
	qa_test 5
}
all_qalocations+=(qalocation_5)

qalocation_6() {
	echo "rpxReplayDelta test"
	qa_test 6
}
all_qalocations+=(qalocation_6)

qalocation_7() {
	echo "rpxNewEntryIntoChain test"
	qa_test 7
}
all_qalocations+=(qalocation_7)

qalocation_8() {
	echo "rpxCommitEntry test"
	qa_test 8 4
}
all_qalocations+=(qalocation_8)

qalocation_9() {
	echo "rpxGetOrSetChunkLocation test"
	qa_test 9
}
all_qalocations+=(qalocation_9)

qalocation_10() {
	echo "rpxUpdateCacheCount test"
	qa_test 10
}
all_qalocations+=(qalocation_10)

qalocation_11() {
	echo "rpxPutCachePartition test"
	qa_test 11
}
all_qalocations+=(qalocation_11)

qalocation_12() {
	echo "rpxRotateDeltaLog test"
	qa_test 12
}
all_qalocations+=(qalocation_12)

qalocation_13() {
	echo "rpxLogDeltaEntry test"
	qa_test 13
}
all_qalocations+=(qalocation_13)

qalocation_14() {
	echo "rpxFlushCache test"
	qa_test 14
}
all_qalocations+=(qalocation_14)

run_qalocation() {
    qalocation=$1
    echo "------ Starting '$qalocation' ------"
    run_test $qalocation
    echo "------ '$qalocation' complete ------"
}

run_all_qalocations() {
	start_dfs

	echo "start qalocation tests"

	for qalocation in "${all_qalocations[@]}"; do
	    run_qalocation $qalocation
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
	run_all_qalocations ;;
[1-9]*)
	run_qalocation qalocation_$cmd
	;;
*)
	echo "unknown command '$1'"
esac
