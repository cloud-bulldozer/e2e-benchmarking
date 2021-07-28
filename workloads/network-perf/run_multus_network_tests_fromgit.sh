#!/usr/bin/env bash
set -x

source ./common.sh

pairs=1

MULTUS=false
if [[ ${MULTUS_CLIENT_NAD} ]]; then
  MULTUS=true
fi
if [[ ${MULTUS_SERVER_NAD} ]]; then
  MULTUS=true
fi

if [[ ${PAIR} ]]; then
  pairs=${PAIR}
fi

if ${MULTUS} ; then
oc -n benchmark-operator delete benchmark/uperf-benchmark-multus-network --wait
if [[ ${MULTUS_SERVER_NAD} ]]; then
  MULTUS_SERVER="server: ${MULTUS_SERVER_NAD}"
fi
if [[ ${MULTUS_CLIENT_NAD} ]]; then
  MULTUS_CLIENT="client: ${MULTUS_CLIENT_NAD}"
fi

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: uperf-benchmark-multus-network
  namespace: benchmark-operator
spec:
  elasticsearch:
    url: $_es
  clustername: $cloud_name
  test_user: ${cloud_name}-multus-ci-${_pair}p
  metadata:
    collection: ${_metadata_collection}
    serviceaccount: backpack-view
    privileged: true
  cerberus_url: "$CERBERUS_URL" 
  workload:
    name: uperf
    args:
      run_id: "$RUN_ID"
      hostnetwork: false
      serviceip: false
      pin: false
      pin_server: ""
      pin_client: ""
      multus:
        enabled: true
        ${MULTUS_SERVER}
        ${MULTUS_CLIENT}
      samples: 3
      pair: $pairs
      nthrs:
        - 1
        - 8
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
  if [ "$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-multus-network -n benchmark-operator -o jsonpath='{.status.state}')" == "Error" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
  oc describe -n benchmark-operator benchmarks/uperf-benchmark-multus-network | grep State | grep Complete
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

compare_uperf_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-multus-network -n benchmark-operator -o jsonpath='{.status.uuid}')
baseline_uperf_uuid=${_baseline_multus_uuid}

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_uperf_uuid},${compare_uperf_uuid} >> uuid.txt
else
  echo ${compare_uperf_uuid} >> uuid.txt
fi

../../utils/touchstone-compare/run_compare.sh uperf ${baseline_uperf_uuid} ${compare_uperf_uuid} ${pairs}
pairs_array=( "${pairs_array[@]}" "compare_output_${pairs}p.yaml" )

python3 csv_gen.py --files $(echo "${pairs_array[@]}") --latency_tolerance=$latency_tolerance --throughput_tolerance=$throughput_tolerance

fi

# Cleanup
rm -rf /tmp/benchmark-operator
rm -f compare_output_*.yaml
exit 0
