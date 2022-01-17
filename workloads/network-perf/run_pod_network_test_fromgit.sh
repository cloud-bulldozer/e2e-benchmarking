#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=pod
export PATH_TO_RIPSAW_UPERF=$1

if [[ -z $PATH_TO_RIPSAW_UPERF ]]; then
    export PATH_TO_RIPSAW_UPERF=ripsaw-uperf-crd.yaml
fi

for pairs in 1 2 4; do
  export UUID=$(uuidgen)
  export pairs
  run_workload $PATH_TO_RIPSAW_UPERF
  if [[ $? != 0 ]]; then
    exit 1
  fi
  BASELINE_UUID=${BASELINE_POD_UUID[${i}]}
  COMPARISON_OUTPUT="${PWD}/pod-${pairs}-pairs.csv"
  run_benchmark_comparison
done

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_pod_network_test
fi
log "Finished workload ${0}"
