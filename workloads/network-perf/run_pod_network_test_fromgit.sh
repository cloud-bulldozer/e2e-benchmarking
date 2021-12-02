#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=pod

for pairs in 1 2 4; do
  export UUID=$(uuidgen)
  export pairs
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  BASELINE_UUID=${BASELINE_POD_UUID[${i}]}
  COMPARISON_OUTPUT="${PWD}/pod-${pairs}-pairs.csv"
  run_benchmark_comparison
done
generate_csv

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_pod_network_test
fi
log "Finished workload ${0}"
