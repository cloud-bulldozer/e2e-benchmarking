#!/usr/bin/env bash
set -x

source ./common.sh
source ../../utils/common.sh

# Scale up/down $_runs times
for x in $(seq 1 $_runs); do
  for size in ${_init_worker_count} ${_scale}; do
    export size
    # Check cluster's health
    if [[ ${CERBERUS_URL} ]]; then
      response=$(curl ${CERBERUS_URL})
      if [ "$response" != "True" ]; then
        echo "Cerberus status is False, Cluster is unhealthy"
        exit 1
      fi
    fi

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
      echo "Current worker count: "${current_workers}
      echo "Desired worker count: "${size}
      if [ $current_workers -ne $size ]; then
          echo "Scaling completed but desired worker count is not equal to current worker count!"
      fi

      if [ "$scale_state" == "1" ] ; then
        echo "Scaling failed"
        exit 1
      fi

      # Check cluster's health
      if [[ ${CERBERUS_URL} ]]; then
        response=$(curl ${CERBERUS_URL})
        if [ "$response" != "True" ]; then
          echo "Cerberus status is False, Cluster is unhealthy"
          exit 1
        fi
      fi
    fi
  done
done
