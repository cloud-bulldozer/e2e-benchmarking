#!/usr/bin/bash -e

set -e

export WORKLOAD=cluster-density
export METRICS_PROFILE=${METRICS_PROFILE:-metrics-aggregated.yaml}
export JOB_ITERATIONS=${JOB_ITERATIONS:-1000}

. common.sh

deploy_operator
check_running_benchmarks
deploy_workload
wait_for_benchmark ${WORKLOAD}
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
exit ${rc}
