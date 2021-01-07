#!/usr/bin/env bash
export WORKLOAD=pod

source ./common.sh

for pairs in 1 2 4; do
  export pairs=${pairs}
  deploy_workload
  wait_for_benchmark
  assign_uuid
  if [[ ${COMPARE} == "true" ]]; then
    run_benchmark_comparison
  fi
  delete_benchmark
done
print_uuid
if [[ ${COMPARE} == "true" ]]; then
  generate_csv
fi
