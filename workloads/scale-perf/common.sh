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
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
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
