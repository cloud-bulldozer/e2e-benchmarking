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
}
