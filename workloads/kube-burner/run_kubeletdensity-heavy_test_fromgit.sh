#!/usr/bin/bash -e

set -e

export WORKLOAD=kubelet-density-heavy
export NODE_COUNT=${NODE_COUNT:-4}
export PODS_PER_NODE=${PODS_PER_NODE:-250}

. common.sh

deploy_operator
label_nodes heavy
deploy_workload
wait_for_benchmark ${WORKLOAD}
unlabel_nodes
exit ${rc}
