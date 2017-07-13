#!/bin/bash

# if SIGINT or SIGTERM are captured, show space saving report
#trap finish SIGINT SIGTERM

TOPDIR=$(dirname $0)/..

. $TOPDIR/tests/cfg.sh
. $TOPDIR/tests/lib.sh

#TESTDIR=$DFS_MNTPNT/testData/set66
TESTDIR=$DFS_MNTPNT/testData/set66

# a directory to store original data
ORIGINALDIR=/tmp/dfsdir
rm -rf $ORIGINALDIR
mkdir -p $ORIGINALDIR
[ -e $TESTDIR ] || mkdir -p $TESTDIR


name=$(basename $DFSD)
# declare a flag when dfsd is down by pkill or fail location
declare STOPPED=""
declare DEDUP_FAILED=""
declare RESTORE_FAILED=""
declare md5sum
declare -i faillocation=1
declare KILLDFSD=""
declare RANDOMNESS=yes
declare FULLTEST=yes
declare TESTLOCATION=""
declare totalblks=0
declare blksafterdedup=0
declare QUICKTEST=""
declare SCANPATH=""
declare COMPREHENSIVETEST=""
declare -i failcount=0
declare filesize
declare script_start=`date +%s%N`
declare deduptime
declare -i i
declare speedsum=0
declare -i speedcount
declare -i realfilenum
declare megabytesum=0
declare chunksum=0

init_test_env

printmsg() {
	echo -n "[`date +%m-%d\ %R:%S`]: "
	echo "$1"
}

# override error() in lib.sh to stop dfsd after error
# avoid create_error() is still running background
error() {
	printmsg "$1"

	test_failed=yes
	while caller $i; do
		i=$((i+1))
	done
	echo "Backup the logs and metadata..."
	local logdir=/tmp/stresstest_`date +%m%d-%H:%M:%S`
	mkdir -p $logdir
	cp /var/log/dfs.log $logdir
	cp /var/log/repo.log $logdir
	cp /tmp/stresstest.log $logdir
	cp -R $MDPATH $logdir/
	# do not stop dfs first
	#$DFS_CLI ctrl stop
	exit 1
}

displaytime() {
  local A=$(echo "$1" | bc)
	local T=$(echo "$A/1000000000" | bc)
  local D=$(echo "$T/60/60/24" | bc)
  local H=$(echo "$T/60/60%24" | bc)
  local M=$(echo "$T/60%60" | bc)
  local S=$(echo "$T%60" | bc)
	local NS=$(echo "$A%1000000000" | bc)
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M
  (( $S > 0 )) && printf '%d seconds' $S && printf ' and '
	echo -n "$NS nanoseconds"
}


# report the space saving
report() {
	local blocks=$($DFS_CLI list -v |\
	 awk -F 'First available block:' 'BEGIN{sum=0} {sum+=$2} END{print sum}')
	local megabytes=$($DFS_CLI list -v |\
	 awk -F 'First available block:' 'BEGIN{sum=0} {sum+=$2} END{print sum/256}')
	local script_running=`date +%s%N`
	local runtime=$(echo "$script_running-$script_start" | bc)
	local dedupspeed=$(echo "scale=3;$filesize*976562.5/1024/$deduptime" | bc)
	speedsum=$(echo "$speedsum+$dedupspeed" | bc)
	let speedcount++
	local average=$(echo "$speedsum/$speedcount" |bc)

	#if [ "$COMPREHENSIVETEST" = "yes" ]; then
	#	for filename in $(find /mnt/dfs -type f -name "*" -size +100k); do
	#		((sum+=$(stat --format=%b $filename)))
	#	done
	#else
	#	for ((k=1;k<=$(ls -l $TESTDIR | grep "^-" | wc -l);k++)); do
	#		((sum+=$(stat --format=%b $TESTDIR/tf$k)))
	#	done
	#fi

	echo ""
	echo "$i files completed, dedup failed $failcount times"
	echo ""
	echo "SUMMARY OF SPACE PERFORMANCE:"
	echo ""
	echo "dfs partition:"
	echo "Before dedup, $totalblks (512B)blocks or \
$(echo "scale=2; $totalblks*512/1024/1024" | bc) MB used."
	echo "After dedup, $blksafterdedup (512B)blocks or \
$(echo "scale=2; $blksafterdedup*512/1024/1024" | bc) MB used."
	echo ""
	echo "repo:"
	echo "$blocks (4K)blocks / $(($blocks*8)) (512B)blocks used in repo."
	echo "$megabytes MB used in repo."
	echo ""
	[ "$megabytes" -lt "$megabytesum" ] &&
	 error "repo size is smaller than last time!"
	megabytesum=$megabytes

	echo "metadata:"
	# clear fail location first
	#$DFS_CLI test_set 0 0
	#$DFS_CLI ctrl flush
	local chunks=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 |\
	 awk -F ' ' 'BEGIN{sum=0} {sum+=cInfo$2} END{print sum}')
	[ -z "$chunks" ] && echo "missing index.meta" && chunks=0
	local sizeofindex=$(stat --format=%b $MDPATH/repo/index)
	local blocksofindex=$(($sizeofindex/8))
	echo "$chunks chunks in repo."
	echo "$blocksofindex (4K)blocks used by index."
	echo ""
	[ "$chunks" -lt "$chunksum" ] && error "chunk number is reset!"
	chunksum=$chunks

	echo "SUMMARY OF TIME PERFORMANCE:"
	echo ""
	echo "Last deduped file tf$i"
	local sizeinMB=$(echo "scale=6;$filesize/1024/1024" | bc)
	echo "size: $sizeinMB MB"
	#echo "size: $filesize MB"
	echo "dedup time: $(displaytime $deduptime)"
	echo "dedup speed: $dedupspeed MB/s"
	echo ""
	echo "Average dedup speed: $average MB/s"
	echo ""
	echo "Script has been running for:"
	displaytime $runtime
	echo ""
}

# set fail location or kill dfsd at a random time
create_random_error() {
	# random number 0-5
	# 0--do nothing
	# 1--kill dfsd before dedup
	# 2-5 set a random fail location
	local -i dice=$(( (RANDOM % 5) +1 ))

	[ $dice = "1" ] && {
		KILLDFSD=yes
		printmsg "DFSD will be killed during the next dedup process..."
	}
	[ $dice -gt "1" ] && {
		# create a random number from 1 to 13
		# if the number is 5, 6, kill dfsd
		# if other number, set the fail location

		local -i test_set=$(( (RANDOM % 16) +1 ))
		#local -i test_set=$(( (RANDOM % 12) +2 ))
		# 5/6/14 -- kill dfsd
		if [ $test_set = "5" -o $test_set = "6" -o $test_set = "14" ]; then
			KILLDFSD=yes
			printmsg "DFSD will be killed during the next dedup process..."
			#continue
		else
			local randomtimes=$(( RANDOM % 2 ))
			printmsg "set QA fail location $test_set $randomtimes"
			$DFS_CLI test_set $test_set $randomtimes
		fi
	}
}

delete_log() {
	rm -f /var/log/dfs.log
	rm -f /var/log/repo.log
}

create_random_restoreerror() {
	local -i dice=$((RANDOM % 3))

	[ $dice = "1" ] && {
		KILLDFSD=yes
		printmsg "DFSD will be killed during the next restore process..."
	}
}

create_fail_location() {
	local test_set=$1
	if [ -z "$test_set" ]; then
		#[[ $faillocation -eq 14 ]] && faillocation=1
		#[[ $faillocation -eq 5 ]] && let faillocation++
		#[[ $faillocation -eq 6 ]] && let faillocation++
		[[ $faillocation -gt 2 ]] && faillocation=4

		printmsg "test_set $faillocation 0"
		$DFS_CLI test_set $faillocation 0

		let faillocation++
	else
		#local randomtimes=$(( RANDOM % 2 ))
		printmsg "test_set $test_set 0"
		$DFS_CLI test_set $test_set 0
	fi
}

gen_random_files() {
	local fileNumber=$1
	local -i dice=$(( RANDOM % 3 ))
	#local -i dice=0
	# dice will be 0, 1 and 2 randomly
	# if dice=0, generate data from /dev/urandom
	[ $dice = "0" ] && {
		local size=$(( ( RANDOM % 46 )  + 1 ))
		printmsg "generate tf$fileNumber by dd, size $size MB"
		dd if=/dev/urandom of=$TESTDIR/tf$fileNumber bs=1M count=$size ||
		 error "dd failed"
		sync
		filesize=$(echo "$size*1024*1024" | bc)
		printmsg "file size is $filesize, copying original data..."
		cp $TESTDIR/tf$fileNumber $ORIGINALDIR/tf$fileNumber
	}

	# if dice=1, generate data from genFileSet
	# with random suffix and random size
	[ $dice = "1" ] && {
		#local raw="$TOPDIR/tests/raw"
		local raw="/tmp/raw"
		local tstDir="$DFS_MNTPNT/testData"
		local suffix=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 3 | head -n 1)

		printmsg "generate tf$fileNumber by genFileSet ,suffix is $suffix"
		$genFileSet 66 $raw $tstDir $suffix $fileNumber
		[ -e $tstDir/set66/tf$fileNumber ] || error "genFileSet failed"
		sync
		#filesize=$(($(stat --format=%s $TESTDIR/tf$fileNumber)/1024/1024))
		filesize=$(echo "$(stat --format=%s $TESTDIR/tf$fileNumber)" | bc)
		printmsg "file size is $filesize, copying original data..."
		cp $TESTDIR/tf$fileNumber $ORIGINALDIR/tf$fileNumber
	}

	# if dice=2, copy a random real file from /var
	[ $dice = "2" ] && {
		[ -e /tmp/filelist ] || error "missing filelist"
		local -i realfilenumber=$(( ( RANDOM % $realfilenum )  + 1 ))
		local realfilename=$(cat /tmp/filelist | sed -n "$realfilenumber,1p")
		if [ -e $realfilename ]; then
			printmsg "copying $realfilename as tf$fileNumber"
			cp $realfilename $TESTDIR/tf$fileNumber || error "cp failed"
			sync
			#filesize=$(($(stat --format=%s $TESTDIR/tf$fileNumber)/1024/1024))
			filesize=$(echo "$(stat --format=%s $TESTDIR/tf$fileNumber)" | bc)
			printmsg "file size is $filesize, copying original data..."
			cp $TESTDIR/tf$fileNumber $ORIGINALDIR/tf$fileNumber
		else
			gen_random_files $fileNumber
		fi
	}
}

gen_files_into_dfspartition() {
	local fileNumber=1
	local des=$1
	local raw="/tmp/raw"
	local max=$2
	[[ -z "$max" ]] && max=0xfff
	for ((i=0x0;i<=$max;i++)); do
		local hexnum=$(printf %X `echo $i`)
		[[ ${#hexnum} -eq 1 ]] &&
		 suffix=$(echo 00$hexnum | tr '[:upper:]' '[:lower:]')
		[[ ${#hexnum} -eq 2 ]] &&
		 suffix=$(echo 0$hexnum | tr '[:upper:]' '[:lower:]')
		[[ ${#hexnum} -eq 3 ]] &&
		 suffix=$(echo $hexnum | tr '[:upper:]' '[:lower:]')
		printmsg "generate tf$fileNumber by genFileSet ,suffix is $suffix"
		$genFileSet 66 $raw $des $suffix $fileNumber
		let fileNumber++
	done
}

gen_files_with_suffix() {
	local fileNumber=$1
	local raw="/tmp/raw"
	local tstDir="$DFS_MNTPNT/testData"
	[[ $fileNumber -gt "4096" ]] && echo "test finished" && exit 1
	local hexnum=$(printf %X `echo $(($fileNumber-1))`)
	[[ ${#hexnum} -eq 1 ]] &&
	 suffix=$(echo 00$hexnum | tr '[:upper:]' '[:lower:]')
	[[ ${#hexnum} -eq 2 ]] &&
	 suffix=$(echo 0$hexnum | tr '[:upper:]' '[:lower:]')
	[[ ${#hexnum} -eq 3 ]] &&
	 suffix=$(echo $hexnum | tr '[:upper:]' '[:lower:]')
	printmsg "generate tf$fileNumber by genFileSet ,suffix is $suffix"
	$genFileSet 66 $raw $tstDir $suffix $fileNumber
}

gen_real_files() {
	local fileNumber=$1
	[ -z "$SCANPATH" ] && SCANPATH=/usr/bin
	local numbers=$(ls -l $SCANPATH | grep "^-" | wc -l)

	if [ $fileNumber -le $numbers ]; then
		local filename=$(ls -l $SCANPATH\
		  | grep "^-" | awk {'print $9'} | sed -n "$fileNumber,1p")
		printmsg "copying $filename to dfs partition..."
		\cp -fr $SCANPATH/$filename $TESTDIR/tf$fileNumber

	elif [ $fileNumber -gt $numbers ]; then
		printmsg "test finished" && exit 0
	fi
	printmsg "copying original data..."
	cp $TESTDIR/tf$fileNumber $ORIGINALDIR/tf$fileNumber
}

dedup_file() {
	local fileNumber=$1
	md5sum=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')

	pgrep $name &> /dev/null || error "Dedup: Maybe there is a fatal error"

	printmsg "Deduping file: tf$fileNumber"
	printmsg "checksum is $md5sum"

	# 0.15-0.25s delay
	local delay=$(( RANDOM%10+15 ))
	[ "$KILLDFSD" = "yes" ] && STOPPED=yes

	local dedup_start=`date +%s%N`

	# kill dfsd randomly while deduping
	[ "$KILLDFSD" = "yes" ] && {
		sleep 0.$delay
		printmsg "pkill -9 dfsd in 0.$delay seconds"
		pkill -9 $name
	} &
	$DFS_CLI dedup $TESTDIR/tf$fileNumber || {
		let failcount++
		printmsg "Dedup failed $failcount times"
		DEDUP_FAILED=yes
	}
	local dedup_finish=`date +%s%N`
	deduptime=$(echo "$dedup_finish-$dedup_start" | bc)
	printmsg "deduptime: $deduptime ns."
	KILLDFSD=""
}

restore_file() {
	local fileNumber=$1

	pgrep $name &> /dev/null || error "Restore: Maybe there is a fatal error"

	printmsg "Restoring file: tf$fileNumber"

	# 0.15-0.25s delay
	local delay=$(( RANDOM%10+15 ))
	[ "$KILLDFSD" = "yes" ] && STOPPED=yes

	# kill dfsd randomly while restoring
	[ "$KILLDFSD" = "yes" ] && {
		sleep 0.$delay
		printmsg "pkill -9 dfsd in 0.$delay seconds"
		pkill -9 $name
	} &
	$DFS_CLI restore $TESTDIR/tf$fileNumber || RESTORE_FAILED=yes
	KILLDFSD=""
}

preprocess_dedup() {
	[[ -e $TESTDIR/tf$fileNumber ]] || error "file tf$fileNumber not exist!"
	printmsg "preprocess_dedup..."
	MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber || error "inspect failed!"
	local fileNumber=$1
	# get the output of "nStubs" from inspect
	local nStubs=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber | awk -F ':' '{print $2}' | tail -n 1 | tr -dc '0-9')
	# get the output of "nFiles" from inspect
	local nFiles=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber | awk -F ':' '{print $3}' | tail -n 1 | tr -dc '0-9')

	# check the status of dfsd before verify
	pgrep $name &> /dev/null || STOPPED=yes

	# if dfsd is running, dedup failed
	# it will be a critical error
	[ -z "$STOPPED" ] && [ "$DEDUP_FAILED" = "yes" ] && {
		error "dfsd is still running, but dedup failed"
		# do some more check
	}

	# if dfsd is down, but dedup is not failed
	# do regular check
	[ "$STOPPED" = "yes" ] && [ -z "$DEDUP_FAILED" ] && {
		 printmsg "dfsd is down but dedup is not failed"
		 STOPPED=""
		 DEDUP_FAILED=""
		 start_dfs

		 preprocess_dedup $fileNumber
	}

	# if dfsd is down and dedup is failed
	[ "$STOPPED" = "yes" ] && [ "$DEDUP_FAILED" = "yes" ] && {
		 # if it is a stub file, it must be deduped
		 [ "$nStubs" = "1" ] && {
			 printmsg "warning, tf$fileNumber is a stub file but dedup failed"
			 start_dfs

			 STOPPED=""
			 DEDUP_FAILED=""
			 preprocess_dedup $fileNumber
		 }

		 # if it is a regular file, check if the file is damaged
		 [ "$nFiles" = "1" ] && {
			 printmsg "Dedup failed since dfsd is shutdown"
			 # if file is not damaged, start dfs, dedup it and verify again
			 STOPPED=""
			 DEDUP_FAILED=""
			 start_dfs

			 dedup_file $fileNumber
			 preprocess_dedup $fileNumber
		 }
	 }
	STOPPED=""
	DEDUP_FAILED=""
}

regularcheck_dedup() {
	# if dfsd is running and dedup succeed
	[ -z "$STOPPED" ] && [ -z "$DEDUP_FAILED" ] && {
		local fileNumber=$1
		local new_md5sum=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')
		#local new_blocks=$(stat --format=%b $TESTDIR/tf$fileNumber)
		printmsg "regular check..."

		$DFS_CLI check $TESTDIR/tf$fileNumber | grep -q 'deduped' ||
		 error "tf$fileNumber not deduped"
		printmsg "Checking md5sum and blocks of tf$fileNumber"
		[ "$md5sum" = "$new_md5sum" ] ||
			error "md5sum mismatch: $md5sum vs. $new_md5sum"
		#[ "$blocks" -gt "$new_blocks" ] ||
		#		error "blocks: $blocks vs. $new_blocks"

		printmsg "Verifying deduped tf$fileNumber"
		MDPATH=$MDPATH $DFS_CLI verify $TESTDIR/tf$fileNumber ||
		 error "verification failed"

		printmsg "Inspecting tf$fileNumber"
		MDPATH=$MDPATH $REPO_INSPECT --verbose 2 --verify \
		--dir $TESTDIR/tf$fileNumber &> /dev/null || error "inspect failed"
	}
}

preprocess_restore() {
	[[ -e $TESTDIR/tf$fileNumber ]] || error "file tf$fileNumber not exist!"
	printmsg "preprocess_restore..."
	MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber || error "inspect failed!"
	local fileNumber=$1
	# get the output of "nStubs" from inspect
	local nStubs=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber | awk -F ':' '{print $2}' | tail -n 1 | tr -dc '0-9')
	# get the output of "nFiles" from inspect
	local nFiles=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 --verify --dir\
	 $TESTDIR/tf$fileNumber | awk -F ':' '{print $3}' | tail -n 1 | tr -dc '0-9')

	# check the status of dfsd before verify
	pgrep $name &> /dev/null || STOPPED=yes

	# if dfsd is running, restore failed
	# it will be a critical error
	[ -z "$STOPPED" ] && [ "$RESTORE_FAILED" = "yes" ] && {
		error "dfsd is still running, but restore failed"
		# do some more check
	}

	# if dfsd is down, but restore is not failed
	# do regular check
	[ "$STOPPED" = "yes" ] && [ -z "$RESTORE_FAILED" ] && {
		 printmsg "dfsd is down but restore is not failed"
		 STOPPED=""
		 RESTORE_FAILED=""
		 start_dfs

		 preprocess_restore $fileNumber
	}

	# if dfsd is down and restore is failed
	[ "$STOPPED" = "yes" ] && [ "$RESTORE_FAILED" = "yes" ] && {
		 # it shoule be a stub file, check if the file is damaged
		 [ "$nStubs" = "1" ] && {

			 printmsg "Restore failed since dfsd is shutdown"
			 # if file is not damaged, start dfs, restore it and verify again
			 STOPPED=""
			 RESTORE_FAILED=""
			 start_dfs

			 restore_file $fileNumber
			 preprocess_restore $fileNumber
		 }

		 # if it is a regular file, do regular check with a warning
		 [ "$nFiles" = "1" ] && {
			 # md5sum and blocks should not be modified
			 local new_md5sum2=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')
			 #local new_blocks2=$(stat --format=%b $TESTDIR/tf$fileNumber)

			 printmsg "Warning: Restore failed, but tf$fileNumber is a regular file."
			 STOPPED=""
			 RESTORE_FAILED=""
			 start_dfs
			 preprocess_restore $fileNumber
		 }
	 }
	STOPPED=""
	RESTORE_FAILED=""
}

regularcheck_restore() {
	# if dfsd is running and restore succeed
	[ -z "$STOPPED" ] && [ -z "$RESTORE_FAILED" ] && {
		local fileNumber=$1
		local new_md5sum=$(md5sum $TESTDIR/tf$fileNumber | awk '{print $1}')
		#local new_blocks=$(stat --format=%b $TESTDIR/tf$fileNumber)
		printmsg "regular check..."

		$DFS_CLI check $TESTDIR/tf$fileNumber | grep -q 'deduped' &&
		 error "tf$fileNumber still deduped"
		printmsg "Checking md5sum and blocks of tf$fileNumber"
		[ "$md5sum" = "$new_md5sum" ] ||
			error "md5sum mismatch: $md5sum vs. $new_md5sum"
		#[ "$blocks" -gt "$new_blocks" ] ||
		#		error "blocks: $blocks vs. $new_blocks"

		printmsg "Comparing restored files with original data..."
		cmp $TESTDIR/tf$fileNumber $ORIGINALDIR/tf$fileNumber &> /dev/null ||
			error "cmp failed: tf$fileNumber"
	}
}

init_test() {
	local fileNumber=$1

	if [ -z "$SCANPATH" ]; then
		[ "$RANDOMNESS" = "yes" ] && {
			gen_random_files $fileNumber
			create_random_error
		}
		[ -z "$RANDOMNESS" ] && {
			gen_files_with_suffix $fileNumber
			create_fail_location $TESTLOCATION
		}
	else
		gen_real_files $fileNumber
		#create_random_error
	fi

	((totalblks+=$(stat --format=%b $TESTDIR/tf$fileNumber)))
	dedup_file $fileNumber
	preprocess_dedup $fileNumber
	((blksafterdedup+=$(stat --format=%b $TESTDIR/tf$fileNumber)))
	regularcheck_dedup $fileNumber
	printmsg "Inspecting repo..."
	MDPATH=$MDPATH $REPO_INSPECT || {
		echo "inspect error, trying to restart dfs"
		stop_dfs
		start_dfs
		sleep 1
		MDPATH=$MDPATH $REPO_INSPECT || error "inspect error"
	}
	[ "$FULLTEST" = "yes" ] && {
		[ "$RANDOMNESS" = "yes" ] && create_random_restoreerror
		restore_file $fileNumber
		preprocess_restore $fileNumber
		regularcheck_restore $fileNumber
		dedup_file $fileNumber
	}
	report
	local diskused=$(df -h | grep "/tmp" | awk '{print $5}' | sed 's/%//g')
	local systemused=$(df -h | grep "/centos-root" | awk '{print $5}' | sed 's/%//g')
	[ "$diskused" -gt "90" ] && {
		printmsg "Disk space is used more than 90%, delete some tested files..."
		rm -f $ORIGINALDIR/*
	}
	[ "$systemused" -gt "95" ] && {
		printmsg "System space is used more than 95%, moving logs..."
		mkdir -p /tmp/log_backup
		mv /var/log/dfs.log /tmp/log_backup/dfs.log.`date +%m%d-%H:%M:%S`
		mv /var/log/repo.log /tmp/log_backup/repo.log.`date +%m%d-%H:%M:%S`
	}
}

run_stresstest() {
	if [ -z "$QUICKTEST" ]; then
		echo "Do you want a full test?"
		echo "enter 1 -- full test"
		echo "enter 2 -- dedup test"
		read value1
		case $value1 in
			1) ;;
			2) FULLTEST="" ;;
			*) echo "unknown command '$value1'" && exit ;;
		esac

		if [ -z "$TESTLOCATION" -a -z "$SCANPATH" ]; then
			echo "Do you want a random test?"
			echo "enter 1 -- with randomness"
			echo "enter 2 -- without randomness"
			read value2
			case $value2 in
				1) ;;
				2) RANDOMNESS="" ;;
				*) echo "unknown command '$value2'" && exit ;;
			esac
		fi

		echo "Do you want to delete dfs.log and repo.log?"
		echo "enter 1 -- not delete"
		echo "enter 2 -- delete"
		read value3
		case $value3 in
			1) ;;
			2) delete_log;;
			*) echo "unknown command '$value3'" && exit ;;
		esac
	fi

	start_dfs
	# set log level to 2
	echo "log 2" > $MDPATH/repo/cfg
	# generate test directory
	[ -e $TESTDIR ] || mkdir -p $TESTDIR
	i=$(($(ls -l $TESTDIR |grep "^-"|wc -l)+1))
	REFORMAT=""
	stop_dfs
	start_dfs

	if [ "$RANDOMNESS" = "yes" ]; then
		find /var -type f -name "*" -size +100k> /tmp/filelist
		realfilenum=$(cat /tmp/filelist | wc -l)
	fi

	while (($i)); do
		init_test $i
		let i++
	done
}

mytest() {
	local faillocation=$1
	while true; do
		#local -i dice=$(( RANDOM % 3 ))
		local -i dice=0
		REFORMAT=yes
		start_dfs
		REFORMAT=""
		echo "genFileSet"
		$genFileSet 88 raw $DFS_MNTPNT/testData
		local md5sum1=$(md5sum $DFS_MNTPNT/testData/set88/tf1 | awk '{print $1}')
		echo "md5sum is $md5sum1"
		\cp -fr $DFS_MNTPNT/testData/set88/tf1 /tmp/111/tf1
		echo "$DFS_CLI test_set $faillocation $dice"
		$DFS_CLI test_set $faillocation $dice
		echo "dedup..."
		$DFS_CLI dedup $DFS_MNTPNT/testData/set88/tf1
		start_dfs
		$DFS_CLI dedup $DFS_MNTPNT/testData/set88/tf1
		MDPATH=$MDPATH $REPO_INSPECT --verbose 1 || error "inspect failed"
	done
}

dedupdir_test() {
	local sourcedir=$1
	local -i count=1
	REFORMAT=yes
	start_dfs
	REFORMAT=""
	delete_log
	echo "log 2" > $MDPATH/repo/cfg
	COMPREHENSIVETEST=yes
	stop_dfs
	start_dfs
	local filename
	local filename2

	#printmsg "copying $sourcedir to /mnt/dfs..."
	#cp -R $sourcedir $DFS_MNTPNT/

	for filename2 in $(find $sourcedir -type f -name "*" -size +100k); do
		printmsg "copying $filename2 to /mnt/dfs..."
		\cp -fr $filename2 $DFS_MNTPNT/
	done

	for filename in $(find /mnt/dfs -type f -name "*" -size +100k); do
		((totalblks+=$(stat --format=%b $filename)))
		printmsg "deduping $filename, count=$count"
		$DFS_CLI dedup $filename || {
			sleep 0.5
			pgrep $name &> /dev/null || printmsg "dfsd crashed!"
			pgrep $name &> /dev/null || start_dfs
			local megabytes=$($DFS_CLI list -v |\
			 awk -F 'First available block:' 'BEGIN{sum=0} {sum+=$2} END{print sum/256}')
			printmsg "$megabytes MB used in repo"
			error "dedup failed"
		}
		printmsg "blocks: $totalblks"
		let count++
	done
	report
}

gen_small_file() {
	local fileNumber=$1
	local -i k
	local tempnum=$((10000+$fileNumber))
	for k in `seq 1 209715` ;do
		echo "${tempnum:1}"
	done > /tmp/dfsdcrashtest/tf$fileNumber
}

dfsd_crashtest() {
	local -i num
	local tempnum
	REFORMAT=yes
	start_dfs
	REFORMAT=""
	delete_log
	echo "log 2" > $MDPATH/repo/cfg
	COMPREHENSIVETEST=yes
	stop_dfs
	start_dfs
	mkdir -p $DFS_MNTPNT/testdir
	for num in `seq 1 4000`; do
		printmsg "generating tf$num..."
		[ -e /tmp/dfsdcrashtest/tf$num ] || gen_small_file $num
		#dd if=/dev/urandom of=$DFS_MNTPNT/testdir/tf$num bs=1M count=1
		cp /tmp/dfsdcrashtest/tf$num $DFS_MNTPNT/testdir/tf$num
		printmsg "deduping tf$num"
		$DFS_CLI dedup $DFS_MNTPNT/testdir/tf$num || error "dfsd crashed!"
	done
}

gen_dd() {
	local fileNumber=$1
	local size=$2
	printmsg "generate tf$fileNumber by dd, size $size MB"
	dd if=/dev/urandom of=$TESTDIR/tf$fileNumber.0 bs=1M count=$size ||
	 error "dd failed"
	sync
}

simultaneous_dedup() {
	local -i fnum=1
	local -i j
	local -i sum
	REFORMAT=yes
	start_dfs
	REFORMAT=""
	delete_log
	echo "log 2" > $MDPATH/repo/cfg
	stop_dfs
	start_dfs
	[ -e $TESTDIR ] || mkdir -p $TESTDIR
	while true; do
		local size=$(( ( RANDOM % 46 )  + 1 ))
		gen_dd $fnum $size
		#generate 5-15 copy of files
		#local copycount=$(( ( RANDOM % 11 ) + 5 ))
		local copycount=5
		printmsg "tf$fnum will be copied for $copycount times"
		for ((j=1;j<=$copycount;j++)); do
			cp $TESTDIR/tf$fnum.0 $TESTDIR/tf$fnum.$j || error "copy tf$fnum failed"
		done
		printmsg "$copycount copies completed"
		printmsg "start deduping these identical files simultaneously"
		for ((j=0;j<=$copycount;j++)); do
			{
				printmsg "deduping tf$fnum.$j"
				$DFS_CLI dedup $TESTDIR/tf$fnum.$j || echo "dedup tf$fnum.$j failed"
			} &
		done
		wait
		$DFS_CLI ctrl flush
		printmsg "checking files are deduped"
		for ((j=0;j<=$copycount;j++)); do
			$DFS_CLI check $TESTDIR/tf$fnum.$j | grep -q 'deduped' ||
			 error "tf$fnum.$j not deduped"
		done
		printmsg "checking repo usage..."
		local MBinrepo=$($DFS_CLI list -v |\
		 awk -F 'First available block:' 'BEGIN{sum=0} {sum+=$2} END{print sum/256}')
		local chunks=$(MDPATH=$MDPATH $REPO_INSPECT --verbose 1 |\
		 awk -F ' ' 'BEGIN{sum=0} {sum+=cInfo$2} END{print sum}')
		((sum+=$size))
		printmsg "total size is $sum MB, there are $MBinrepo MB/ $chunks chunks in repo"
		[ "$sum" -eq "$MBinrepo" ] || error "size mismatch"
		[ "$sum" -eq "$chunks" ] || error "chunks mismatch"
		let fnum++
	done
}

cmd=$1
[ -z "$cmd" ] && cmd=reformat

case $cmd in
reformat)
	REFORMAT=yes
	run_stresstest 2>&1  | tee /tmp/stresstest.log
	;;
generate)
	gen_files_into_dfspartition $ORIGINALDIR $2;;
generatedfs)
	gen_files_into_dfspartition $DFS_MNTPNT/testData $2;;
noreformat)
	run_stresstest 2>&1  | tee /tmp/stresstest.log ;;
suffix)
	gen_files_with_suffix $2 ;;
location)
	TESTLOCATION=$2
	[ -z "$TESTLOCATION" ] && error "Please set up a fail location."
	echo "fail location selected $TESTLOCATION"
	RANDOMNESS=""
	REFORMAT=yes
	run_stresstest 2>&1  | tee /tmp/stresstest.log
	;;
-q)
	delete_log
	QUICKTEST=yes
	REFORMAT=yes
	run_stresstest 2>&1  | tee /tmp/stresstest.log
	;;
mytest)
	mytest $2 2>&1  | tee /tmp/mytest.log;;
realfile)
	SCANPATH=$2
	REFORMAT=yes
	run_stresstest 2>&1  | tee /tmp/stresstest.log
	;;
dedupdir)
	dedupdir_test $2 2>&1  | tee /tmp/stresstest.log;;
dfsd)
	dfsd_crashtest 2>&1 | tee /tmp/stresstest.log;;
time)
	displaytime $2;;
multiple)
	simultaneous_dedup 2>&1 | tee /tmp/stresstest.log;;
[1-9]*)
	init_test $2 ;;
*)
	echo "unknown command '$1'"
esac
