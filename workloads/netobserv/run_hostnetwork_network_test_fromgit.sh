#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=hostnet
export HOSTNETWORK=true
export pairs=1
export UUID=$(uuidgen)

deploy_netobserv_operator
run_workload ripsaw-uperf-crd.yaml
if [[ $? != 0 ]]; then
  exit 1
fi

delete_flowcollector
export UUID=$(uuidgen)
run_workload ripsaw-uperf-crd.yaml

BASELINE_UUID=${BASELINE_HOSTNET_UUID}
COMPARISON_OUTPUT="${PWD}/hostnet.csv"
run_benchmark_comparison

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_hostnetwork_test
fi
log "Finished workload ${0}"
