#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

# Check if the old mount point exists, and if so clean it up
if [ -d /dev/cgroup ]
then
  if grep -q /dev/cgroup /proc/mounts
  then
    umount /dev/cgroup
  fi

  rmdir /dev/cgroup
fi

cgroup_path=/tmp/warden/cgroup

mkdir -p $cgroup_path

if grep "${cgroup_path} " /proc/mounts | cut -d' ' -f3 | grep -q cgroup
then
  find $cgroup_path -mindepth 1 -type d | sort | tac | xargs rmdir
  umount $cgroup_path
fi

# Mount tmpfs
if ! grep "${cgroup_path} " /proc/mounts | cut -d' ' -f3 | grep -q tmpfs
then
  mount -t tmpfs none $cgroup_path
fi

# Mount cgroup subsystems individually
for subsystem in cpu cpuacct devices memory
do
  mkdir -p $cgroup_path/$subsystem

  if ! grep -q "${cgroup_path}/$subsystem " /proc/mounts
  then
    mount -t cgroup -o $subsystem none $cgroup_path/$subsystem
  fi
  mkdir -p $cgroup_path/$subsystem/sys
  chown work:work $cgroup_path/$subsystem/sys/*
  mkdir -p $cgroup_path/$subsystem/dea
done 

#init cpu
(( cpu_sys=${CPU_TOTAL}*${CPU_SYS_PERCENT}/100))
(( cpu_dea=${CPU_TOTAL}*${CPU_DEA_PERCENT}/100))
/bin/echo $cpu_sys > $cgroup_path/cpu/sys/cpu.shares
/bin/echo $cpu_dea > $cgroup_path/cpu/dea/cpu.shares

#init memory
(( mem_sys=${MEM_TOTAL}*${MEM_SYS_PERCENT}/100))
(( mem_dea=${MEM_TOTAL}*${MEM_DEA_PERCENT}/100))
/bin/echo ${mem_sys}M > $cgroup_path/memory/sys/memory.limit_in_bytes
/bin/echo ${mem_dea}M > $cgroup_path/memory/dea/memory.limit_in_bytes


./net.sh setup

# Disable AppArmor if possible
if [ -x /etc/init.d/apparmor ]; then
  /etc/init.d/apparmor teardown
fi

# quotaon(8) exits with non-zero status when quotas are ENABLED
if [ "$DISK_QUOTA_ENABLED" = "true" ] && quotaon -p $CONTAINER_DEPOT_MOUNT_POINT_PATH > /dev/null
then
  mount -o remount,usrjquota=aquota.user,grpjquota=aquota.group,jqfmt=vfsv0 $CONTAINER_DEPOT_MOUNT_POINT_PATH
  quotacheck -ugmb -F vfsv0 $CONTAINER_DEPOT_MOUNT_POINT_PATH
  quotaon $CONTAINER_DEPOT_MOUNT_POINT_PATH
elif [ "$DISK_QUOTA_ENABLED" = "false" ] && ! quotaon -p $CONTAINER_DEPOT_MOUNT_POINT_PATH > /dev/null
then
  quotaoff $CONTAINER_DEPOT_MOUNT_POINT_PATH
fi
