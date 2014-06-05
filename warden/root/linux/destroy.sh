#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

if [ $# -ne 1  ]
then
  echo "Usage: $0 <instance_path>"
  exit 1
fi

target=$1

# Ignore tmp directory
if [ $(basename $target) == "tmp" ]
then
  exit 0
fi

function mount_path_in_dead_container
{
  [[-d $backup_path/$id/tmp/rootfs/$1 ]] || mkdir -p $backup_path/$id/tmp/rootfs/$1
  mount -n --bind $rootfs_path/$1 $backup_path/$id/tmp/rootfs/$1
  mount -n --bind -o remount,ro $rootfs_path/$1 $backup_path/$id/tmp/rootfs/$1
}
if [ -d $target ]
then
  if [ -f $target/destroy.sh ]
  then
    $target/destroy.sh
  fi
  source $target/etc/config
  if [[ $backup == "true" ]]
  then
    [[ -d $backup_path ]] || mkdir -p $backup_path && mv $target $backup_path
    if [[ -d $backup_path ]]
    then
      mount_path_in_dead_container bin 
      mount_path_in_dead_container lib
      mount_path_in_dead_container lib64
      mount_path_in_dead_container sbin
      mount_path_in_dead_container usr
    fi
  else
    rm -rf $target
  fi
fi
