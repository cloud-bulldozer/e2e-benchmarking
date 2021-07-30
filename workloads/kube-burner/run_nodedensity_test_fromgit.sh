#!/usr/bin/bash -e

set -e

NODE_COUNT=${NODE_COUNT:-4}
PODS_PER_NODE=${PODS_PER_NODE:-250}
export WORKLOAD=node-density
export REMOTE_CONFIG=https://raw.githubusercontent.com/rsevilla87/e2e-benchmarking/kube-burner-workloads/workloads/kube-burner/workloads/node-pod-density/node-pod-density.yml
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/rsevilla87/e2e-benchmarking/kube-burner-workloads/workloads/kube-burner/metrics-profiles/metrics.yml}

. common.sh

deploy_operator
check_running_benchmarks
label_nodes regular
deploy_workload
wait_for_benchmark ${WORKLOAD}
unlabel_nodes
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
exit ${rc}
