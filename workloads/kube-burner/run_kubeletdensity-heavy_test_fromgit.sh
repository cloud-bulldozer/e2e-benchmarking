#!/usr/bin/bash -e

set -e

export WORKLOAD=kubelet-density-heavy
export METRICS_PROFILE=${METRICS_PROFILE:-metrics.yaml}
export NODE_COUNT=${NODE_COUNT:-4}
export PODS_PER_NODE=${PODS_PER_NODE:-250}

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
