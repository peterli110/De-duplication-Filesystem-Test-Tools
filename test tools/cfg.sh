#!/bin/bash

REFORMAT=${REFORMAT:-"no"}
MDPATH=${MDPATH:-/tmp/dfsmd}
DISK0=${DISK0:-/tmp/dfsrepo-disk0}
DISK1=${DISK1:-/tmp/dfsrepo-disk1}
DISKCOUNT=${DISKCOUNT:-2}
DISKSIZE=${DISKSIZE:-200}

DFS_DISK=${DFS_DISK:-/tmp/dfs-disk}
DFS_DISKSIZE=${DFS_DISKSIZE:-200}
DFS_MNTPNT=${DFS_MNTPNT:-/mnt/dfs}
