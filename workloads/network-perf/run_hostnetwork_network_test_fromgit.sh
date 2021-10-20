#!/usr/bin/env bash
export WORKLOAD=hostnet

source ./common.sh
export HOSTNETWORK=true
export pairs=1

run_workload ripsaw-uperf-crd.yaml
if [[ $? != 0 ]]; then
  exit 1
fi
assign_uuid
run_benchmark_comparison
generate_csv

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_hostnetwork_test
fi
