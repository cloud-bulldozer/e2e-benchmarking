#!/bin/bash
set -x

source common.sh

deploy_operator
if [[ ${DEPLOY_LOGGING} == "true" ]]; then
  deploy_logging_stack
fi
run_workload
wait_for_benchmark
if [[ ${TEST_CLEANUP} == "true" ]]; then
  cleanup
fi
exit ${rc}
