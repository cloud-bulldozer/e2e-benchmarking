#!/usr/bin/bash -e

set -e

export WORKLOAD=pod-density
export TEST_JOB_ITERATIONS=${PODS:-1000}
export REMOTE_CONFIG=${REMOTE_CONFIG:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/workloads/node-pod-density/node-pod-density.yml}
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/metrics-profiles/metrics.yml}

. common.sh

deploy_operator
check_running_benchmarks
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi 
deploy_workload
wait_for_benchmark ${WORKLOAD}
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 snappy_backup kube-burner-poddensity
fi

exit ${rc}
