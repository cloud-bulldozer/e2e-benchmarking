#!/usr/bin/env bash

source ./common.sh
source ../../utils/common.sh

log "Starting test for cloud: ${CLOUD_NAME}"
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
      current_workers=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/workload!="" --ignore-not-found | grep -v NAME | wc -l`
      log "Current worker count: "${current_workers}
      log "Desired worker count: "${size}
      if [ $current_workers -ne $size ]; then
          log "Scaling completed but desired worker count is not equal to current worker count!"
      fi

      if [ "$scale_state" == "1" ] ; then
        log "Scaling failed"
        exit 1
      fi
    fi
  done
done
