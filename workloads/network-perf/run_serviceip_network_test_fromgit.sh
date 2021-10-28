#!/usr/bin/env bash
export WORKLOAD=service

source ./common.sh
export SERVICEIP=true

for pairs in 1 2 4; do
  export pairs
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  assign_uuid
  run_benchmark_comparison
done
generate_csv

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_serviceip_network_test
fi
log "Finished workload ${0}"
