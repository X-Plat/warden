#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./etc/config

filter_forward_chain="warden-forward"
filter_default_chain="warden-default"
filter_instance_prefix="warden-instance-"
filter_instance_chain="${filter_instance_prefix}${id}"
nat_prerouting_chain="warden-prerouting"
nat_instance_prefix="warden-instance-"
nat_instance_chain="${filter_instance_prefix}${id}"

external_ip=$(ip route get 10.212.0.231 | sed 's/.*src\s\(.*\)\s/\1/;tx;d;:x')

function teardown_filter() {
  # Prune forward chain
  iptables -S ${filter_forward_chain} 2> /dev/null |
    grep "\-g ${filter_instance_chain}\b" |
    sed -e "s/-A/-D/" |
    xargs --no-run-if-empty --max-lines=1 iptables

  # Flush and delete instance chain
  iptables -F ${filter_instance_chain} 2> /dev/null || true
  iptables -X ${filter_instance_chain} 2> /dev/null || true
}

function setup_filter() {
  teardown_filter

  # Create instance chain
  iptables -N ${filter_instance_chain}
  iptables -A ${filter_instance_chain} \
    --goto ${filter_default_chain}

  # Bind instance chain to forward chain
  iptables -I ${filter_forward_chain} \
    --in-interface ${network_host_iface} \
    --goto ${filter_instance_chain}
}

function teardown_nat() {
  # Prune prerouting chain
  iptables -t nat -S ${nat_prerouting_chain} 2> /dev/null |
    grep "\-j ${nat_instance_chain}\b" |
    sed -e "s/-A/-D/" |
    xargs --no-run-if-empty --max-lines=1 iptables -t nat

  # Flush and delete instance chain
  iptables -t nat -F ${nat_instance_chain} 2> /dev/null || true
  iptables -t nat -X ${nat_instance_chain} 2> /dev/null || true
}

function setup_nat() {
  teardown_nat

  # Create instance chain
  iptables -t nat -N ${nat_instance_chain}

  # Bind instance chain to prerouting chain
  iptables -t nat -A ${nat_prerouting_chain} \
    --jump ${nat_instance_chain}
}

# Lock execution
mkdir -p ../tmp
exec 3> ../tmp/$(basename $0).lock
flock -x -w 10 3

case "${1}" in
  "setup")
    setup_filter
    setup_nat

    ;;

  "teardown")
    teardown_filter
    teardown_nat

    ;;

  "in")
    if [ -z "${HOST_PORT:-}" ]; then
      echo "Please specify HOST_PORT..." 1>&2
      exit 1
    fi

    if [ -z "${CONTAINER_PORT:-}" ]; then
      echo "Please specify CONTAINER_PORT..." 1>&2
      exit 1
    fi

    if [ "${CONTAINER_PORT}" -ne 22 ]; then
      iptables -t nat -A ${nat_instance_chain} \
        --protocol tcp \
        --destination "${external_ip}" \
        --destination-port "${HOST_PORT}" \
        --jump DNAT \
        --to-destination "${network_container_ip}:${CONTAINER_PORT}"
    fi

    ;;

  "out")
    if [ -z "${NETWORK:-}" ] && [ -z "${PORT:-}" ]; then
      echo "Please specify NETWORK and/or PORT..." 1>&2
      exit 1
    fi

    opts=""

    if [ -n "${NETWORK:-}" ]; then
      opts="${opts} --destination ${NETWORK}"
    fi

    # Restrict protocol to tcp when port is specified
    if [ -n "${PORT:-}" ]; then
      opts="${opts} --protocol tcp"
      opts="${opts} --destination-port ${PORT}"
    fi

    iptables -I ${filter_instance_chain} 1 ${opts} --jump RETURN

    ;;
  "get_ingress_info")
    if [ -z "${ID:-}" ]; then
      echo "Please specify container ID..." 1>&2
      exit 1
    fi
    tc filter show dev w-${ID}-0 parent ffff:

    ;;
  "get_egress_info")
    if [ -z "${ID:-}" ]; then
      echo "Please specify container ID..." 1>&2
      exit 1
    fi
    tc qdisc show dev w-${ID}-0

    ;;
  *)
    echo "Unknown command: ${1}" 1>&2
    exit 1

    ;;
esac
