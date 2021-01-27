#!/usr/bin/bash -e

set -e

export WORKLOAD=kubelet-density
export METRICS_PROFILE=${METRICS_PROFILE:-metrics.yaml}
export JOB_ITERATIONS=${PODS:-25000}

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
