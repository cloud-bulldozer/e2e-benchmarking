#!/usr/bin/env bash

source env.sh
source ../../utils/benchmark-operator.sh

log() {
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

if [[ -z ${SCALE} ]]; then
  log "Scale target not set. Exiting"
fi

deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
  rm -rf benchmark-operator
  git clone --single-branch --branch ${OPERATOR_BRANCH} ${OPERATOR_REPO} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
  kubectl apply -f benchmark-operator/resources/scale_role.yaml
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z backpack-view
}

run_workload() {
  log "Deploying benchmark"
  local TMPCR=$(mktemp)
  envsubst < $1 > ${TMPCR}
  run_benchmark ${TMPCR} ${TEST_TIMEOUT}
  local rc=$?
  if [[ ${TEST_CLEANUP} == "true" ]]; then
    log "Cleaning up benchmark"
    kubectl delete -f ${TMPCR}
  fi
  return ${rc}
}

index_result() {
  local INIT_WORKER_COUNT=$1
  local FINAL_WORKER_COUNT=$2
  local START_DATE=$3
  local END_DATE=$4
  local DURATION=$5

  local ES_INDEX="openshift-scale-timings"

  log "Indexing scale data to Elasticsearch"
  local VERSION_INFO=$(oc version -o json)
  local INFRA_INFO=$(oc get infrastructure.config.openshift.io cluster -o json)
  local PLATFORM=$(echo ${INFRA_INFO} | jq -r .status.platformStatus.type)
  local CLUSTER_NAME=$(echo ${INFRA_INFO} | jq -r .status.infrastructureName)
  local OCP_VERSION=$(echo ${VERSION_INFO} | jq -r .openshiftVersion)
  local K8S_VERSION=$(echo ${VERSION_INFO} | jq -r .serverVersion.gitVersion)
  local SDN_TYPE=$(oc get networks.operator.openshift.io cluster -o jsonpath="{.spec.defaultNetwork.type}")
  local UUID=$(oc get benchmark -n benchmark-operator ${BENCHMARK} -o json | jq -r '.status.uuid')

local DATA=$(cat << EOF
{
"uuid":"${UUID}",
"platform":"${PLATFORM}",
"ocp_version":"${OCP_VERSION}",
"k8s_version":"${K8S_VERSION}",
"sdn_type":"${SDN_TYPE}",
"timestamp":"${START_DATE}",
"end_date":"${END_DATE}",
"init_worker_count": "${INIT_WORKER_COUNT}",
"final_worker_count": "${FINAL_WORKER_COUNT}",
"scale_duration": "${DURATION}"
}
EOF
)

  # send the document to ES
  log "Indexing benchmark metadata to ${ES_SERVER}/${ES_INDEX}"
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${ES_INDEX}/_doc -d "${DATA}" -o /dev/null
}
