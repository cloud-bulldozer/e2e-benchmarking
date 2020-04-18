#!/usr/bin/env bash
set -x

source ./common.sh

_baseline_svc_1p_uuid=
_baseline_svc_2p_uuid=
_baseline_svc_4p_uuid=

if [[ ${BASELINE_SVC_1P_UUID} ]]; then
  _baseline_svc_1p_uuid=${BASELINE_SVC_1P_UUID}
fi

if [[ ${BASELINE_SVC_2P_UUID} ]]; then
  _baseline_svc_2p_uuid=${BASELINE_SVC_2P_UUID}
fi

if [[ ${BASELINE_SVC_4P_UUID} ]]; then
  _baseline_svc_4p_uuid=${BASELINE_SVC_4P_UUID}
fi

oc -n my-ripsaw delete benchmark/uperf-benchmark

for pairs in 1 2 4  #number of uperf client-server pairs
do

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
  test_user: ${cloud_name}-serviceip-ci-${pairs}p
  metadata_collection: ${_metadata_collection}
  metadata_sa: backpack-view
  metadata_privileged: true
  workload:
    name: uperf
    args:
      hostnetwork: false
      serviceip: true
      pin: $pin
      pin_server: "$server"
      pin_client: "$client"
      multus:
        enabled: false
      samples: 3
      pair: ${pairs}
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

if [[ ${COMPARE} == "true" ]] ; then
  if [ "${pairs}" == "1" ] ; then
    baseline_uperf_uuid=${_baseline_svc_1p_uuid}
  elif [ "${pairs}" == "2" ] ; then
    baseline_uperf_uuid=${_baseline_svc_2p_uuid}
  elif [ "${pairs}" == "4" ] ; then
    baseline_uperf_uuid=${_baseline_svc_4p_uuid}
  fi
  compare_uperf_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io -o json | jq -r .items[].status.uuid)
  echo "Comparing current test uuid ${compare_uperf_uuid} with baseline uuid ${baseline_uperf_uuid}"
  ./run_network_compare.sh ${baseline_uperf_uuid} ${compare_uperf_uuid}
fi

oc -n my-ripsaw delete benchmark/uperf-benchmark

done

# Cleanup
rm -rf /tmp/ripsaw

exit 0
