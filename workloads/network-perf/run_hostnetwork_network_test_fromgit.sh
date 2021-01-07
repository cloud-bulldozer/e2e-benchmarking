#!/usr/bin/env bash
export WORKLOAD=hostnet

source ./common.sh
export pairs=1

deploy_workload
wait_for_benchmark
assign_uuid
delete_benchmark
if [[ ${COMPARE} == "true" ]]; then
  run_benchmark_comparison
  generate_csv
fi
print_uuid
