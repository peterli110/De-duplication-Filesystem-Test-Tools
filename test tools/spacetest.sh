#!/bin/bash

TOPDIR=$(dirname $0)/..

. $TOPDIR/tests/cfg.sh
. $TOPDIR/tests/lib.sh

init_test_env

calculate_blocks() {
	local testset=$DFS_MNTPNT/testData/set99/tf
	local sum=0
	for ((i=1;i<=30;i++)); do
		{
			((sum+=$(stat --format=%b $testset$i)))
		}
	done
	echo "$sum 512B blocks used in dfs partition."
}

blocks_used_inrepo() {
	local blocks=$($DFS_CLI list -v |\
	 awk -F 'First available block:' 'BEGIN{sum=0} {sum+=$2} END{print sum}')
	echo "$blocks 4K blocks / $(($blocks*8)) 512B blocks used in repo."
}

numof_chunks_vs_sizeof_index() {
	echo "Flushing cache..."
	$DFS_CLI ctrl flush
	#local chunks=$(MDPATH=$MDPATH $REPO_INSPECT --verbose=1 | awk -F ' ' '/cInfo/{print $2}')
	local chunks=$(MDPATH=/tmp/dfsmd/ src/inspect --verbose=1 |\
	 awk -F ' ' 'BEGIN{sum=0} {sum+=cInfo$2} END{print sum}')
	[ -z "$chunks" ] && error "missing index.meta"
	local sizeofindex=$(stat --format=%b $MDPATH/repo/index)
	local blocksofindex=$(($sizeofindex/8))
	echo "There are $chunks chunks in repo, while index used $blocksofindex 4K blocks."
	if [[ $(($chunks/10)) -lt $(($blocksofindex/10-1)) ]] || [[ $(($chunks/10)) -gt $(($blocksofindex/10+1)) ]]
	then
		echo "There are significant difference between number of chunks and sizeof index."
	fi
}

genfileset() {
	raw="$TOPDIR/tests/raw"
	tstDir="$DFS_MNTPNT/testData"
	fSet="$tstDir/set99"
	rm -rf $fSet
	echo "$genFileSet $fSetNumber $raw $tstDir"
	$genFileSet 99 $raw $tstDir
}

test() {
	REFORMAT="yes"
	start_dfs

	genfileset
	echo -n "Before dedup: "
	calculate_blocks
	echo "Deduping..."
	#$DFS_CLI Dedup $DFS_MNTPNT/testData/set99 || error "dedup failed"
	for ((i=1;i<=30;i++)); do
		{
			$DFS_CLI dedup $DFS_MNTPNT/testData/set99/tf$i || error "dedup failed"
		}
	done
	echo -n "After dedup: "
	calculate_blocks

	blocks_used_inrepo
	numof_chunks_vs_sizeof_index
}

test
