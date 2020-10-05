#!/usr/bin/env bash
set -x

source ./common.sh

oc -n my-ripsaw delete benchmark/scale --ignore-not-found --wait

# Scale up/down $_runs times
for x in $(seq 1 $_runs); do
  for size in ${_init_worker_count} ${_scale}; do
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
      cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: scale
  namespace: my-ripsaw
spec:
  uuid: $_uuid
  elasticsearch:
    server: $_es
    port: $_es_port
  clustername: $cloud_name
  metadata:
    collection: ${_metadata_collection}
    privileged: true
    targeted: false
    serviceaccount: backpack-view
  test_user: ${cloud_name}-scale
  workload:
    name: scale_openshift
    args:
      label:
        key: node-role.kubernetes.io/workload
        value: ""
      tolerations:
        key: role
        value: workload
        effect: NoSchedule
      scale: $size
      serviceaccount: scaler
      poll_interval: $_poll_interval
      post_sleep: $_post_sleep
EOF

      sleep 30

      scale_state=1
      for i in $(seq 1 $_timeout); do
        current_workers=`oc get nodes -l node-role.kubernetes.io/worker= | grep -v NAME | wc -l`
        echo "Current worker count: "${current_workers}
        echo "Desired worker count: "${size}
        oc describe -n my-ripsaw benchmarks/scale | grep State | grep Complete
        if [ $? -eq 0 ]; then
          echo "Scaling Complete"
          scale_state=$?
          break
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

  done
done

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_uuid},${_uuid} >> uuid.txt
else
  echo ${_uuid} >> uuid.txt
fi

# Cleanup
rm -rf /tmp/ripsaw
exit 0
