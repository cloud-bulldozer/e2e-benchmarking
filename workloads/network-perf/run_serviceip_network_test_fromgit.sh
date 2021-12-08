#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=service
export SERVICEIP=true

for pairs in 1 2 4; do
  export UUID=$(uuidgen)
  export pairs
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  BASELINE_UUID=${BASELINE_SVC_UUID[${i}]}
  COMPARISON_OUTPUT="${PWD}/service-${pairs}-pairs.csv"
  run_benchmark_comparison
done

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_serviceip_network_test
fi
log "Finished workload ${0}"
