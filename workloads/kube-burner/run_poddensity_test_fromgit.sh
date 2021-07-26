#!/usr/bin/bash -e

set -e

export WORKLOAD=pod-density
export METRICS_PROFILE=${METRICS_PROFILE:-metrics.yaml}
export TEST_JOB_ITERATIONS=${PODS:-1000}

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
