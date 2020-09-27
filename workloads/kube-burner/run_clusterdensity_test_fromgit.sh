#!/usr/bin/bash -e

set -e

export JOB_ITERATIONS=${JOB_ITERATIONS:-1000}

. common.sh

if [[ ${TAINT_NODE} == 1 ]] && [[ ! -z ${WORKLOAD_NODE} ]]; then
  taint_node ${WORKLOAD_NODE}
fi

deploy_operator
deploy_workload
wait_for_benchmark ${WORKLOAD}
exit ${rc}
