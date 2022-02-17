#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=service
export SERVICEIP=true

export UUID=$(uuidgen)
for pairs in 1 2 4; do
  export pairs
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
done
BASELINE_UUID=${BASELINE_POD_UUID}
COMPARISON_OUTPUT="${PWD}/service-all-pairs.csv"
run_benchmark_comparison


if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_serviceip_network_test
fi
log "Finished workload ${0}"
