#!/usr/bin/env bash
export WORKLOAD=pod
export CRD=smoke-crd.yaml
source ./common.sh

for pairs in 1 2 4
do
export pairs=${pairs}
deploy_workload
wait_for_benchmark
assign_uuid
run_benchmark_comparison
delete_benchmark
done
print_uuid
generate_csv
