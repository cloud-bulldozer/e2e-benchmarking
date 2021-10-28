#!/usr/bin/env bash
export WORKLOAD=pod

source ./common.sh

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
  snappy_backup network_perf_pod_network_test
fi
log "Finished workload run_pod_network_test_fromgit.sh"
