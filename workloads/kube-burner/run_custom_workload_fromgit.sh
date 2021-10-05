#!/usr/bin/bash

set -e

export WORKLOAD=custom

. common.sh

deploy_operator
check_running_benchmarks
run_workload kube-burner-crd.yaml
rc=$?
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
exit ${rc}
