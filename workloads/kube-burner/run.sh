#!/usr/bin/bash

. common.sh

deploy_operator
check_running_benchmarks

case ${WORKLOAD} in
  cluster-density)
    WORKLOAD_TEMPLATE=workloads/cluster-density/cluster-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export TEST_JOB_ITERATIONS=${JOB_ITERATIONS:-1000}
  ;;
  node-density)
    WORKLOAD_TEMPLATE=workloads/node-pod-density/node-pod-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    NODE_COUNT=${NODE_COUNT:-4}
    PODS_PER_NODE=${PODS_PER_NODE:-250}
    label_nodes regular
  ;;
  node-density-heavy)
    WORKLOAD_TEMPLATE=workloads/node-density-heavy/node-density-heavy.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    NODE_COUNT=${NODE_COUNT:-4}
    PODS_PER_NODE=${PODS_PER_NODE:-250}
    label_nodes heavy
  ;;
  pod-density)
    WORKLOAD_TEMPLATE=workloads/node-pod-density/node-pod-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    export TEST_JOB_ITERATIONS=${PODS:-1000}
  ;;
  pod-density-heavy)
    WORKLOAD_TEMPLATE=workloads/node-density-heavy/node-density-heavy.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    export TEST_JOB_ITERATIONS=${PODS:-1000}
  ;;
  max-namespaces)
    WORKLOAD_TEMPLATE=workloads/max-namespaces/max-namespaces.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export TEST_JOB_ITERATIONS=${NAMESPACE_COUNT:-1000}
  ;;
  max-services)
    WORKLOAD_TEMPLATE=workloads/max-services/max-services.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export TEST_JOB_ITERATIONS=${SERVICE_COUNT:-1000}
  ;;
  custom)
  ;;
  *)
     log "Unkonwn workload ${WORKLOAD}, exiting"
     exit 1
  ;;
esac

log "###############################################"
log "Workload: ${WORKLOAD}"
log "Metrics profile: ${METRICS_PROFILE}"
log "QPS: ${QPS}"
log "Burst: ${BURST}"
log "Job iterations: ${TEST_JOB_ITERATIONS}"
if [[ ${WORKLOAD} == node-density* ]]; then
  log "Node count: ${NODE_COUNT}"
  log "Pods per node: ${PODS_PER_NODE}"
fi
log "###############################################"
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi 
run_workload kube-burner-crd.yaml
rc=$?
if [[ ${WORKLOAD} == node-density* ]]; then
  unlabel_nodes
fi
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
delete_pprof_secrets
if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup kube-burner-${WORKLOAD}
fi

exit ${rc}
