#!/usr/bin/env bash
export WORKLOAD=pod

source ./common.sh
export NETWORK_POLICY=true

for pairs in 1 2 4; do
  export UUID=$(uuidgen)
  export pairs=${pairs}
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  assign_uuid
  run_benchmark_comparison
done
generate_csv
log "Finished workload ${0}"
