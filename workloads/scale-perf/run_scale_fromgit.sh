#!/usr/bin/env bash
set -x

source ./common.sh
source ../../utils/common.sh

# Scale up/down $_runs times
for x in $(seq 1 $_runs); do
  oc -n benchmark-operator delete benchmark/scale --ignore-not-found --wait
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
        envsubst < rosa_scale.yaml | oc create -f -
      else
        envsubst < default_scale.yaml | oc create -f -
      fi
      # Get the uuid of newly created scale benchmark.
      long_uuid=$(get_uuid 30)
      if [ $? -ne 0 ];
      then
        exit 1
      fi

      uuid=${long_uuid:0:8}

      # Checks the presence of scale pod. Should exit if pod is not available.
      scale_pod=$(get_pod "app=scale-$uuid" 300)
      if [ $? -ne 0 ];
      then
        exit 1
      fi

      check_pod_ready_state $scale_pod 150s
      if [ $? -ne 0 ];
      then
        echo "Pod wasn't able to move into Running state! Exiting...."
        exit 1
      fi

      scale_state=1
      for i in $(seq 1 $_timeout); do
        current_workers=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/workload!="" --ignore-not-found | grep -v NAME | wc -l`
        echo "Current worker count: "${current_workers}
        echo "Desired worker count: "${size}
        oc describe -n benchmark-operator benchmarks/scale | grep State | grep Complete
        if [ $? -eq 0 ]; then

          if [ $current_workers -eq $size ]; then
            echo "Scaling Complete"
            scale_state=$?
            break
          else
            echo "Scaling completed but desired worker count is not equal to current worker count!"
            break
          fi
        fi
        sleep 60
      done

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
    oc -n benchmark-operator delete benchmark/scale --ignore-not-found --wait
    sleep 10
  done
done

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_uuid},${_uuid} >> uuid.txt
else
  echo ${_uuid} >> uuid.txt
fi

# Cleanup
rm -rf /tmp/benchmark-operator
exit 0
