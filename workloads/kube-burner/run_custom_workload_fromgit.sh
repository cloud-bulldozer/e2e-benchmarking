#!/usr/bin/bash -e

set -e

export WORKLOAD=custom

. common.sh

deploy_operator
check_running_benchmarks
run_workload
wait_for_benchmark ${WORKLOAD}
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
exit ${rc}
