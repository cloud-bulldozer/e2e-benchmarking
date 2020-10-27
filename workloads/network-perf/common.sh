#!/usr/bin/env bash
set -x

pip3 install -r requirements.txt

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

_es=${ES_SERVER:=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com}
_es_port=${ES_PORT:=80}
_es_baseline=${ES_SERVER_BASELINE:=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com}
_es_baseline_port=${ES_PORT_BASELINE:=80}
_metadata_collection=${METADATA_COLLECTION:=true}
COMPARE=${COMPARE:=false}
gold_sdn=${GOLD_SDN:=openshiftsdn}
throughput_tolerance=${THROUGHPUT_TOLERANCE:=5}
latency_tolerance=${LATENCY_TOLERANCE:=5}
client_server_pairs=(1 2 4)

if [[ ${ES_SERVER} ]] && [[ ${ES_PORT} ]] && [[ ${ES_USER} ]] && [[ ${ES_PASSWORD} ]]; then
  _es=${ES_USER}:${ES_PASSWORD}@${ES_SERVER}
fi

if [[ ${ES_SERVER_BASELINE} ]] && [[ ${ES_PORT_BASELINE} ]] && [[ ${ES_USER_BASELINE} ]] && [[ ${ES_PASSWORD_BASELINE} ]]; then
  _es_baseline=${ES_USER_BASELINE}:${ES_PASSWORD_BASELINE}@${ES_SERVER_BASELINE}
fi

if [[ -z "$GSHEET_KEY_LOCATION" ]]; then
   export GSHEET_KEY_LOCATION=$HOME/.secrets/gsheet_key.json
fi

if [[ ${COMPARE} = "true" ]] && [[ ${COMPARE_WITH_GOLD} == "true" ]]; then
  platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' | tr '[:upper:]' '[:lower:]')
  gold_index=$(curl -X GET   "${ES_GOLD}/openshift-gold-${platform}-results/_search" -H 'Content-Type: application/json' -d ' {"query": {"term": {"version": '\"${GOLD_OCP_VERSION}\"'}}}')
  BASELINE_HOSTNET_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."hostnetwork"."num_pairs"."1"."uuid"')
  BASELINE_POD_1P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."podnetwork"."num_pairs"."1"."uuid"')
  BASELINE_POD_2P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."podnetwork"."num_pairs"."2"."uuid"')
  BASELINE_POD_4P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."podnetwork"."num_pairs"."4"."uuid"')
  BASELINE_SVC_1P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."serviceip"."num_pairs"."1"."uuid"')
  BASELINE_SVC_2P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."serviceip"."num_pairs"."2"."uuid"')
  BASELINE_SVC_4P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."serviceip"."num_pairs"."4"."uuid"')
fi

_baseline_hostnet_uuid=${BASELINE_HOSTNET_UUID}
_baseline_pod_1p_uuid=${BASELINE_POD_1P_UUID}
_baseline_pod_2p_uuid=${BASELINE_POD_2P_UUID}
_baseline_pod_4p_uuid=${BASELINE_POD_4P_UUID}
_baseline_svc_1p_uuid=${BASELINE_SVC_1P_UUID}
_baseline_svc_2p_uuid=${BASELINE_SVC_2P_UUID}
_baseline_svc_4p_uuid=${BASELINE_SVC_4P_UUID}

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

# check if cluster is up
date
oc get clusterversion
if [ $? -ne 0 ]; then
  echo "Workload Failed for cloud $cloud_name, Unable to connect to the cluster"
  exit 1
fi

if [[ ${COMPARE} == "true" ]]; then
  echo $BASELINE_CLOUD_NAME,$cloud_name > uuid.txt
else
  echo $cloud_name > uuid.txt
fi

echo "Starting test for cloud: $cloud_name"

rm -rf /tmp/ripsaw

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
oc patch scc restricted --type=merge -p '{"allowHostNetwork": true}'
