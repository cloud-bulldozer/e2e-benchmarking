#!/usr/bin/env bash

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


operator_repo=${OPERATOR_REPO:=https://github.com/cloud-bulldozer/benchmark-operator.git}
operator_branch=${OPERATOR_BRANCH:=master}
export _es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
_es_baseline=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export _metadata_collection=${METADATA_COLLECTION:=false}
export _poll_interval=${POLL_INTERVAL:=5}
export _post_sleep=${POST_SLEEP:=0}
_timeout=${TIMEOUT:=240}
_runs=${RUNS:=1}
export _workload_node_role=${WORKLOAD_NODE_ROLE:=worker}

if [[ -n $SCALE ]]; then
  _scale=${SCALE}
else
  echo "Scale target not set. Exiting"
  exit 1
fi

if [[ -n $UUID ]]; then
  export _uuid=${UUID}
else
  export _uuid=$(uuidgen)
fi

export cloud_name="test_cloud"


# Get initial worker count
_init_worker_count=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= | wc -l`


deploy_operator() {
  deploy_benchmark_operator ${operator_repo} ${operator_branch}
  rm -rf benchmark-operator
  git clone --single-branch --branch ${operator_branch} ${operator_repo} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
  kubectl apply -f benchmark-operator/resources/scale_role.yaml
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z backpack-view
}

run_workload() {
  local TMPCR=$(mktemp)
  log "Deploying benchmark"
  envsubst < $1 > ${TMPCR}
  run_benchmark ${TMPCR} 7200
}

echo "Starting test for cloud: $cloud_name"
deploy_operator
