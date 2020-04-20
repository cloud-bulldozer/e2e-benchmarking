#!/usr/bin/env bash
set -x

source ./common.sh

pairs=1

if [[ ${COMPARE} == "true" ]]; then
  _baseline_multus_uuid=
fi 

if [[ ${BASELINE_MULTUS_UUID} ]]; then
  _baseline_multus_uuid=${BASELINE_MULTUS_UUID}
fi

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
oc -n my-ripsaw delete benchmark/uperf-benchmark

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
  name: uperf-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: $_es
    port: $_es_port
  clustername: $cloud_name
  test_user: ${cloud_name}-multus-ci-${_pair}p
  metadata:
    collection: ${_metadata_collection}
    serviceaccount: backpack-view
    privileged: true
  workload:
    name: uperf
    args:
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
  oc describe -n my-ripsaw benchmarks/uperf-benchmark | grep State | grep Complete
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

compare_uperf_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io -n my-ripsaw -o json | jq -r .items[].status.uuid)
baseline_uperf_uuid=${_baseline_multus_uuid}

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_uperf_uuid},${compare_uperf_uuid} >> uuid.txt
else
  echo ${compare_uperf_uuid} >> uuid.txt
fi

./run_network_compare.sh ${baseline_uperf_uuid} ${compare_uperf_uuid} ${pairs}
pairs_array=( "${pairs_array[@]}" "compare_output_${pairs}p.yaml" )

oc -n my-ripsaw delete benchmark/uperf-benchmark

python3 csv_gen.py --files $(echo "${pairs_array[@]}") --latency_tolerance=$latency_tolerance --throughput_tolerance=$throughput_tolerance

fi

# Cleanup
rm -rf /tmp/ripsaw
rm -f compare_output_*.yaml
exit 0
