#!/usr/bin/bash -e

set -e

export WORKLOAD=pod-density
export JOB_ITERATIONS=${PODS:-1000}
export REMOTE_CONFIG=https://raw.githubusercontent.com/rsevilla87/e2e-benchmarking/kube-burner-workloads/workloads/kube-burner/workloads/node-pod-density/node-pod-density.yml
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/rsevilla87/e2e-benchmarking/kube-burner-workloads/workloads/kube-burner/metrics-profiles/metrics.yml}

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
