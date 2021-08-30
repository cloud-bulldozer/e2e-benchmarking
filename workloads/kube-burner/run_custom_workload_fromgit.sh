#!/usr/bin/bash -e

set -e

export TEST_JOB_ITERATIONS=${PODS:-1000}
export REMOTE_CONFIG=${REMOTE_CONFIG}
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE}

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
