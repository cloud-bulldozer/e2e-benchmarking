#!/usr/bin/env bash
set -x

_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80
_metadata_collection=true
_baseline_multus_uuid=

if [[ ${ES_SERVER} ]]; then
  _es=${ES_SERVER}
fi

if [[ ${ES_PORT} ]]; then
  _es_port=${ES_PORT}
fi

if [[ ${METADATA_COLLECTION} ]]; then
  _metadata_collection=${METADATA_COLLECTION}
fi

if [[ ${BASELINE_MULTUS_UUID} ]]; then
  _baseline_multus_uuid=${BASELINE_MULTUS_UUID}
fi

kubeconfig=$2
if [ "$cloud_name" == "" ]; then
  kubeconfig="$HOME/kubeconfig"
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

MULTUS=false
if [[ ${MULTUS_CLIENT_NAD} ]]; then
  MULTUS=true
fi
if [[ ${MULTUS_SERVER_NAD} ]]; then
  MULTUS=true
fi

_pair=1
if [[ ${PAIR} ]]; then
  _pair=${PAIR}
fi

echo "Starting test for cloud: $cloud_name"

oc create ns my-ripsaw

git clone http://github.com/cloud-bulldozer/ripsaw /tmp/ripsaw
oc apply -f /tmp/ripsaw/deploy
oc apply -f /tmp/ripsaw/resources/backpack_role.yaml
oc apply -f /tmp/ripsaw/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc apply -f /tmp/ripsaw/resources/operator.yaml

server=""
client=""
pin=false
if [[ $(oc get nodes | grep worker | wc -l) -gt 1 ]]; then
  server=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | head -n 1)
  client=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | tail -n 1)
  pin=true
fi

oc adm policy -n my-ripsaw add-scc-to-user privileged -z benchmark-operator
oc adm policy -n my-ripsaw add-scc-to-user privileged -z backpack-view

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
  metadata_collection: ${_metadata_collection}
  metadata_sa: backpack-view
  metadata_privileged: true
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
      pair: ${_pair}
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

if [[ ${COMPARE} == "true" ]] ; then
  baseline_uperf_uuid=${_baseline_multus_uuid}
  compare_uperf_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io -o json | jq -r .items[].status.uuid)
  echo "Comparing current test uuid ${compare_uperf_uuid} with baseline uuid ${baseline_uperf_uuid}"
  ./run_network_compare.sh ${baseline_uperf_uuid} ${compare_uperf_uuid}
fi

oc -n my-ripsaw delete benchmark/uperf-benchmark

fi

# Cleanup
rm -rf /tmp/ripsaw

exit 0

