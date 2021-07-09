#!/usr/bin/bash -e

set -e

export WORKLOAD=networkpolicy-case3
export METRICS_PROFILE=${METRICS_PROFILE:-metrics-aggregated.yaml}
export TEST_JOB_ITERATIONS=${NAMESPACE_COUNT:-5}

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
