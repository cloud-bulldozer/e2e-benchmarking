#!/usr/bin/env bash
set -e

export WORKLOAD=cluster-density
export METRICS_PROFILE=${METRICS_PROFILE:-metrics-aggregated.yaml}
export TEST_JOB_ITERATIONS=${JOB_ITERATIONS:-100}

. common.sh

deploy_operator
check_running_benchmarks
deploy_workload
wait_for_benchmark ${WORKLOAD}
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
#exit ${rc}

export MCP_SIZE=1
export MCP_NODE_COUNT=10
