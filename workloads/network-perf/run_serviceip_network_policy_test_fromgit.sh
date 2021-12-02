#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=service
export NETWORK_POLICY=true
export SERVICEIP=true

if [[ "${isBareMetal}" == "true" ]]; then
  export METADATA_TARGETED=true
fi

for pairs in 1 2 4; do
  export UUID=$(uuidgen)
  export pairs=${pairs}
  COMPARISON_OUTPUT="${PWD}/service-networkpolicy-${pairs}-pairs.csv"
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  BASELINE_UUID=${BASELINE_SVC_UUID[${i}]}
  run_benchmark_comparison
done
generate_csv
log "Finished workload ${0}"
