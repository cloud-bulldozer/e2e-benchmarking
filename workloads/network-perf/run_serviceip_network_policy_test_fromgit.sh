#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=service
export NETWORK_POLICY=true
export SERVICEIP=true

if [[ "${isBareMetal}" == "true" ]]; then
  export METADATA_TARGETED=true
fi

export UUID=$(uuidgen)
for pairs in 1 2 4; do
  export pairs=${pairs}
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
done
BASELINE_UUID=${BASELINE_SVC_UUID}
COMPARISON_OUTPUT="${PWD}/service-networkpolicy-all-pairs.csv"
run_benchmark_comparison

log "Finished workload ${0}"
