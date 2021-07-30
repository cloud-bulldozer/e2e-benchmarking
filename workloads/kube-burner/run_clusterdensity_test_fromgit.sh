#!/usr/bin/bash -e

set -e

export REMOTE_CONFIG=https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/workloads/cluster-density/cluster-density.yml
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/metrics-profile/metrics-aggregated.yml}

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
