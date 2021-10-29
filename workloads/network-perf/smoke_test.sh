#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=pod

for pairs in 1 2 4; do
  export pairs=${pairs}
  run_workload smoke-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  run_benchmark_comparison
done

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_smoke_test
fi
log "Finished workload ${0}"
