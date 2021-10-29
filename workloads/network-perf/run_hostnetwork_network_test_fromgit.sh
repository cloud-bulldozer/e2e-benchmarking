#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=hostnet
export HOSTNETWORK=true
export pairs=1

run_workload ripsaw-uperf-crd.yaml
if [[ $? != 0 ]]; then
  exit 1
fi
BASELINE_UUID=${BASELINE_HOSTNET_UUID}
run_benchmark_comparison

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_hostnetwork_test
fi
log "Finished workload ${0}"
