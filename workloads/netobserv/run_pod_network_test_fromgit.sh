#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=pod

for pairs in 1 2 4; do
  export pairs
  COMPARISON_OUTPUT="${PWD}/pod-${pairs}-pairs-w-netobserv.csv"
  run_perf_test_w_netobserv
  COMPARISON_OUTPUT="${PWD}/pod-${pairs}-pairs-wo-netobserv.csv"
  run_perf_test_wo_netobserv
  if [[ $? != 0 ]]; then
    exit 1
  fi
done

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_pod_network_test
fi
log "Finished workload ${0}"
