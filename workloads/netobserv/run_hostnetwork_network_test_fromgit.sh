#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=hostnet
export HOSTNETWORK=true
export pairs=1

BASELINE_UUID=${BASELINE_HOSTNET_UUID}
COMPARISON_OUTPUT="${PWD}/hostnet-w-netobserv.csv"
run_perf_test_w_netobserv
COMPARISON_OUTPUT="${PWD}/hostnet-wo-netobserv.csv"
run_perf_test_wo_netobserv
if [[ $? != 0 ]]; then
  exit 1
fi

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_hostnetwork_test
fi
log "Finished workload ${0}"
