#!/usr/bin/bash -e

set -e

NODE_COUNT=${NODE_COUNT:-4}
PODS_PER_NODE=${PODS_PER_NODE:-250}
export WORKLOAD=node-density-heavy
export REMOTE_CONFIG=${REMOTE_CONFIG:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/workloads/node-density-heavy/node-density-heavy.yml}
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/metrics-profiles/metrics.yml}

. common.sh

deploy_operator
check_running_benchmarks
label_nodes heavy
deploy_workload
wait_for_benchmark ${WORKLOAD}
unlabel_nodes
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
exit ${rc}
