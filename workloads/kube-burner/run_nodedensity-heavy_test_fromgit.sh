#!/usr/bin/bash

WORKLOAD_TEMPLATE=workloads/node-density-heavy/node-density-heavy.yml
METRICS_PROFILE=${METRICS_PROFILE:-metrics.yaml}
NODE_COUNT=${NODE_COUNT:-4}
PODS_PER_NODE=${PODS_PER_NODE:-250}
export WORKLOAD=node-density-heavy

. common.sh

deploy_operator
check_running_benchmarks
label_nodes heavy
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi 
run_workload kube-burner-crd.yaml
rc=$?
unlabel_nodes
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup ${WORKLOAD}
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup kube-burner-nodedensityheavy
fi

exit ${rc}
