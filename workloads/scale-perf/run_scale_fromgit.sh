#!/usr/bin/env bash

source ./common.sh
source ../../utils/common.sh

openshift_login

log "Starting test for cloud: ${CLOUD_NAME}"
start_time=$(date +%s)
deploy_operator

# Get initial worker count
_init_worker_count=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= | wc -l`
# Scale up/down $_runs times
for x in $(seq 1 ${RUNS}); do
  for size in ${_init_worker_count} ${SCALE}; do
    export size
    if [[ $x -eq 1 && $size -eq $_init_worker_count ]]
    then
      # Don't try to scale down on the first iteration
      :
    else
      if [[ ${ROSA_CLUSTER_NAME} ]] ; then
        export ROSA_CLUSTER_NAME ROSA_ENVIRONMENT ROSA_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
        run_workload rosa_scale.yaml
      else
        run_workload default_scale.yaml
      fi
      if [[ $? != 0 ]]; then
        log "Scaling failed"
        exit 1
      fi
      current_workers=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/workload!="" --ignore-not-found | grep -v NAME | wc -l`
      log "Current worker count: "${current_workers}
      log "Desired worker count: "${size}
      if [ $current_workers -ne $size ]; then
        log "Scaling completed but desired worker count is not equal to current worker count!"
        exit 1
      fi
      sleep 10
    fi
  done
done
end_time=$(date +%s)
duration=$(date -ud@$((${end_time} - ${start_time})) +%T)
log "Duration of execution: ${duration} for number of scale runs: ${RUNS}"
remove_benchmark_operator
