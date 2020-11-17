#!/usr/bin/env bash
set -x

source ./common.sh

pairs=(1)

oc -n my-ripsaw delete benchmark/uperf-benchmark-hostnetwork --wait

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: uperf-benchmark-hostnetwork
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: $_es
    port: $_es_port
  clustername: $cloud_name
  test_user: ${cloud_name}-hostnetwork-ci
  metadata:
    collection: ${_metadata_collection}
    serviceaccount: backpack-view
    privileged: true
  cerberus_url: "$CERBERUS_URL" 
  workload:
    name: uperf
    args:
      hostnetwork: true
      serviceip: false
      pin: $pin
      pin_server: "$server"
      pin_client: "$client"
      multus:
        enabled: false
      samples: 3
      pair: 1
      nthrs:
        - 1
      protos:
        - tcp
        - udp
      test_types:
        - stream
        - rr
      sizes:
        - 64
        - 1024
        - 16384
      runtime: 60
EOF

sleep 30

uperf_state=1
for i in {1..240}; do
  if [ "$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-hostnetwork -n my-ripsaw -o jsonpath='{.status.state}')" == "Error" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
  oc describe -n my-ripsaw benchmarks/uperf-benchmark-hostnetwork | grep State | grep Complete
  if [ $? -eq 0 ]; then
          echo "UPerf Workload done"
          uperf_state=$?
          break
  fi
  sleep 60
done

if [ "$uperf_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi

compare_uperf_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-hostnetwork -n my-ripsaw -o jsonpath='{.status.uuid}')
baseline_uperf_uuid=${_baseline_hostnet_uuid}

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_uperf_uuid},${compare_uperf_uuid} >> uuid.txt
else
  echo ${compare_uperf_uuid} >> uuid.txt
fi

../run_compare.sh ${baseline_uperf_uuid} ${compare_uperf_uuid} ${pairs}
pairs_array=( "${pairs_array[@]}" "compare_output_${pairs}p.yaml" )

python3 csv_gen.py --files $(echo "${pairs_array[@]}") --latency_tolerance=$latency_tolerance --throughput_tolerance=$throughput_tolerance

# Cleanup
rm -rf /tmp/ripsaw
rm -f compare_output_*.yaml
exit 0
