#!/usr/bin/bash

WORKLOAD_TEMPLATE=workloads/max-namespaces/max-namespaces.yml
METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
export TEST_JOB_ITERATIONS=${NAMESPACE_COUNT:-1000}
export WORKLOAD=max-namespaces

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
  cleanup
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup kube-burner-maxnamespaces
fi

exit ${rc}
