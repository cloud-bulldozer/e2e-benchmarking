#!/usr/bin/bash

WORKLOAD_TEMPLATE=workloads/node-pod-density/node-pod-density.yml
METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
export TEST_JOB_ITERATIONS=${PODS:-1000}
export WORKLOAD=pod-density

. common.sh

deploy_operator
check_running_benchmarks
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi 
run_workload kube-burner-crd.yaml
rc=$?
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup ${WORKLOAD}
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup kube-burner-poddensity
fi

exit ${rc}
