#!/usr/bin/env bash
set -x

source ./common.sh

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

oc -n my-ripsaw delete benchmark/scale --ignore-not-found

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: scale
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: $_es
    port: $_es_port
  clustername: $cloud_name
  metadata:
    collection: ${_metadata_collection}
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
      scale: $_scale
      serviceaccount: scaler
      poll_interval: $_poll_interval
      post_sleep: $_post_sleep
EOF
      
sleep 30

scale_state=1
for i in {1..240}; do
  if [ "$(oc get benchmarks.ripsaw.cloudbulldozer.io -n my-ripsaw -o jsonpath='{.items[0].status.state}')" == "Error" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
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

compare_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io -n my-ripsaw -o jsonpath='{.items[0].status.uuid}')

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_uuid},${compare_uuid} >> uuid.txt
else
  echo ${compare_uuid} >> uuid.txt
fi

# run_scale_compare.sh ${baseline_uperf_uuid} ${compare_uperf_uuid} ${pairs}

oc -n my-ripsaw delete benchmark/scale

# python3 csv_gen.py --files $(echo "${pairs_array[@]}") --latency_tolerance=$latency_tolerance --throughput_tolerance=$throughput_tolerance

# Cleanup
rm -rf /tmp/ripsaw
rm -f compare_output_*.yaml
exit 0
