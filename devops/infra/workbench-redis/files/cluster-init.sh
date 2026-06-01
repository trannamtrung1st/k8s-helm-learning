#!/bin/sh
# Bootstrap or grow a Redis Cluster from REDIS_NODES (space-separated host:port).
# Requires: REDIS_USER, REDIS_NODES.
# Optional: REDISCLI_AUTH, CLUSTER_REPLICAS (replicas per master, default 0), CLUSTER_MASTERS,
#   CLUSTER_VERIFY_ATTEMPTS (default 3), CLUSTER_VERIFY_WAIT_SEC (default 5).
set -eu

: "${REDIS_USER:?REDIS_USER is required}"
: "${REDIS_NODES:?REDIS_NODES is required (space-separated host:port list)}"

CLUSTER_REPLICAS="${CLUSTER_REPLICAS:-0}"
CLUSTER_MASTERS="${CLUSTER_MASTERS:-0}"
VERIFY_ATTEMPTS="${CLUSTER_VERIFY_ATTEMPTS:-3}"
VERIFY_WAIT_SEC="${CLUSTER_VERIFY_WAIT_SEC:-5}"

if [ -n "${REDISCLI_AUTH:-}" ]; then
  export REDISCLI_AUTH
fi

redis_cli() {
  redis-cli --user "${REDIS_USER}" "$@"
}

host_part() {
  echo "${1%%:*}"
}

port_part() {
  echo "${1##*:}"
}

node_count() {
  # shellcheck disable=SC2086
  set -- ${REDIS_NODES}
  echo $#
}

validate_node_layout() {
  total=$(node_count)
  per_master=$((CLUSTER_REPLICAS + 1))
  if [ $((total % per_master)) -ne 0 ]; then
    echo "ERROR: ${total} nodes cannot form ${CLUSTER_MASTERS} masters × ${per_master} (master + replicas) layout." >&2
    exit 1
  fi
  derived_masters=$((total / per_master))
  if [ "${CLUSTER_MASTERS}" -gt 0 ] && [ "${derived_masters}" -ne "${CLUSTER_MASTERS}" ]; then
    echo "ERROR: expected ${CLUSTER_MASTERS} masters from node count, got ${derived_masters}." >&2
    exit 1
  fi
  if [ "${CLUSTER_MASTERS}" -eq 0 ]; then
    CLUSTER_MASTERS=${derived_masters}
  fi
  echo "Layout: ${CLUSTER_MASTERS} masters, ${CLUSTER_REPLICAS} replica(s) per master, ${total} nodes."
}

wait_for_nodes() {
  for node in ${REDIS_NODES}; do
    echo "Waiting for ${node}..."
    until redis_cli -h "$(host_part "${node}")" -p "$(port_part "${node}")" ping 2>/dev/null | grep -q PONG; do
      sleep 2
    done
  done
}

cluster_state_ok() {
  node=$1
  redis_cli -h "$(host_part "${node}")" -p "$(port_part "${node}")" cluster info 2>/dev/null \
    | grep -q 'cluster_state:ok'
}

find_anchor() {
  for node in ${REDIS_NODES}; do
    if cluster_state_ok "${node}"; then
      echo "${node}"
      return 0
    fi
  done
  return 1
}

node_id() {
  node=$1
  redis_cli -h "$(host_part "${node}")" -p "$(port_part "${node}")" cluster myid 2>/dev/null \
    | tr -d '[:space:]'
}

node_in_cluster() {
  target=$1
  anchor=$2
  tid=$(node_id "${target}") || return 1
  [ -n "${tid}" ] || return 1
  redis_cli -h "$(host_part "${anchor}")" -p "$(port_part "${anchor}")" cluster nodes \
    | grep -q "^${tid} "
}

find_master_needing_replica() {
  anchor=$1
  ah=$(host_part "${anchor}")
  ap=$(port_part "${anchor}")
  redis_cli -h "${ah}" -p "${ap}" cluster nodes | awk -v need="${CLUSTER_REPLICAS}" '
    $3 ~ /master/ { master[$1] = $2; slaves[$1] = 0 }
    $3 ~ /slave/  { slaves[$4]++ }
    END {
      for (id in master) {
        if (slaves[id] + 0 < need) {
          gsub(/@.*/, "", master[id])
          print master[id]
          exit
        }
      }
    }
  '
}

list_nodes() {
  echo "Configured nodes:${REDIS_NODES}"
  anchor=$1
  if [ -n "${anchor}" ]; then
    echo "Cluster members (from ${anchor}):"
    redis_cli -h "$(host_part "${anchor}")" -p "$(port_part "${anchor}")" cluster nodes \
      | awk '{print "  " $2 " " $3}'
  fi
}

create_cluster() {
  echo "Creating cluster (${CLUSTER_MASTERS} masters, ${CLUSTER_REPLICAS} replica(s) per master):${REDIS_NODES}"
  # shellcheck disable=SC2086
  redis-cli --cluster create ${REDIS_NODES} \
    --cluster-replicas "${CLUSTER_REPLICAS}" \
    --user "${REDIS_USER}" \
    --cluster-yes
}

add_missing_nodes() {
  anchor=$1
  added=0
  rebalance=0
  for node in ${REDIS_NODES}; do
    if node_in_cluster "${node}" "${anchor}"; then
      echo "Already in cluster: ${node}"
      continue
    fi
    if [ "${CLUSTER_REPLICAS}" -gt 0 ]; then
      master_ep=$(find_master_needing_replica "${anchor}")
      if [ -n "${master_ep}" ]; then
        echo "Adding replica ${node} to master ${master_ep}"
        redis-cli --cluster add-node "${node}" "${master_ep}" \
          --cluster-slave \
          --user "${REDIS_USER}" \
          --cluster-yes
        added=$((added + 1))
        continue
      fi
    fi
    echo "Adding master ${node} via anchor ${anchor}"
    redis-cli --cluster add-node "${node}" "${anchor}" \
      --user "${REDIS_USER}" \
      --cluster-yes
    added=$((added + 1))
    rebalance=1
  done
  if [ "${rebalance}" -eq 1 ]; then
    echo "Rebalancing slots onto new master(s)..."
    redis-cli --cluster rebalance "${anchor}" \
      --cluster-use-empty-masters \
      --user "${REDIS_USER}" \
      --cluster-yes
  elif [ "${added}" -gt 0 ]; then
    echo "Added ${added} replica(s); no slot rebalance needed."
  else
    echo "No new nodes to add."
  fi
}

check_cluster_layout() {
  anchor=$1
  ah=$(host_part "${anchor}")
  ap=$(port_part "${anchor}")
  if ! cluster_state_ok "${anchor}"; then
    echo "  cluster_state not ok on ${anchor}" >&2
    return 1
  fi
  masters=$(redis_cli -h "${ah}" -p "${ap}" cluster nodes | awk '$3 ~ /master/ { c++ } END { print c+0 }')
  replicas=$(redis_cli -h "${ah}" -p "${ap}" cluster nodes | awk '$3 ~ /slave/ { c++ } END { print c+0 }')
  members=$(redis_cli -h "${ah}" -p "${ap}" cluster nodes | wc -l | tr -d ' ')
  expected=$(node_count)
  expected_replicas=$((CLUSTER_MASTERS * CLUSTER_REPLICAS))
  ok=1
  if [ "${members}" -ne "${expected}" ]; then
    echo "  members: ${members}/${expected}" >&2
    ok=0
  fi
  if [ "${masters}" -ne "${CLUSTER_MASTERS}" ]; then
    echo "  masters: ${masters}/${CLUSTER_MASTERS}" >&2
    ok=0
  fi
  if [ "${replicas}" -ne "${expected_replicas}" ]; then
    echo "  replicas: ${replicas}/${expected_replicas}" >&2
    ok=0
  fi
  if [ "${ok}" -eq 0 ]; then
    return 1
  fi
  echo "  verified: ${masters} masters, ${replicas} replicas, ${members} members" >&2
  return 0
}

wait_verify_cluster_layout() {
  attempt=1
  anchor=""
  while [ "${attempt}" -le "${VERIFY_ATTEMPTS}" ]; do
    echo "Verify attempt ${attempt}/${VERIFY_ATTEMPTS}..." >&2
    if anchor=$(find_anchor); then
      if check_cluster_layout "${anchor}"; then
        printf '%s\n' "${anchor}"
        return 0
      fi
      echo "Cluster reachable but layout not complete yet." >&2
    else
      echo "No node reports cluster_state:ok yet." >&2
    fi
    if [ "${attempt}" -lt "${VERIFY_ATTEMPTS}" ]; then
      echo "Waiting ${VERIFY_WAIT_SEC}s for cluster to settle..." >&2
      sleep "${VERIFY_WAIT_SEC}"
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

main() {
  validate_node_layout
  wait_for_nodes

  if anchor=$(find_anchor); then
    echo "Cluster already exists (anchor: ${anchor})."
    list_nodes "${anchor}"
    add_missing_nodes "${anchor}"
  else
    echo "Cluster does not exist yet."
    list_nodes ""
    create_cluster
  fi

  anchor=$(wait_verify_cluster_layout) || {
    echo "ERROR: cluster layout verification failed after ${VERIFY_ATTEMPTS} attempt(s)." >&2
    exit 1
  }
  echo "Cluster ready (anchor: ${anchor})."
  list_nodes "${anchor}"
}

main "$@"
