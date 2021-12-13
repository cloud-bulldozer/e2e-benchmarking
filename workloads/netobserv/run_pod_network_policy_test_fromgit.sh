#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=pod
export NETWORK_POLICY=true

for pairs in 1 2 4; do
  export UUID=$(uuidgen)
  export pairs=${pairs}
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  BASELINE_UUID=${BASELINE_POD_UUID[${i}]}
  COMPARISON_OUTPUT="${PWD}/pod-networkpolicy-${pairs}-pairs.csv"
  run_benchmark_comparison
done
generate_csv
log "Finished workload ${0}"
