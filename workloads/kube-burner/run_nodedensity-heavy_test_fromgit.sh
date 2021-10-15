#!/usr/bin/bash -e

set -e

WORKLOAD_TEMPLATE=workloads/node-density-heavy/node-density-heavy.yml
METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
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
deploy_workload
wait_for_benchmark ${WORKLOAD}
unlabel_nodes
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 snappy_backup kube-burner-nodedensityheavy
fi

exit ${rc}
