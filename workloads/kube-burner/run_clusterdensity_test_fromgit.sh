#!/usr/bin/bash -e

set -e

export JOB_ITERATIONS=${JOB_ITERATIONS:-1000}

. common.sh

deploy_operator
deploy_workload
wait_for_benchmark ${WORKLOAD}
exit ${rc}
