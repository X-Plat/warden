#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)

source ./etc/config

if [ -f ./run/wshd.pid ]
then
  echo "wshd is already running..."
  exit 1
fi

./net.sh setup

nice -n 10 ./bin/wshd --run ./run --lib ./lib --root ./mnt --title "wshd: $id" \
  1> ./run/wshd.out.log \
  2> ./run/wshd.err.log

if id rd &>/dev/null; then
  chown rd:rd run/wshd.sock
fi
