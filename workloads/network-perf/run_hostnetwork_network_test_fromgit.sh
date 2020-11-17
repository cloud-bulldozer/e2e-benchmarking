#!/usr/bin/env bash
export WORKLOAD=hostnet

source ./common.sh
export pairs=1

deploy_workload
wait_for_benchmark
assign_uuid
run_benchmark_comparison
delete_benchmark
print_uuid
generate_csv
