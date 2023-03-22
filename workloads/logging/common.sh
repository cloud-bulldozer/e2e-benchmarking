#!/usr/bin/env bash
source env.sh
source ../../utils/benchmark-operator.sh
source ../../utils/common.sh

openshift_login

# Logging format
log() {
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}

# Check if oc client is installed
log "Checking if oc client is installed"

deploy_operator() {
  deploy_benchmark_operator
}

deploy_logging_stack() {
  log "Deploying logging stack"
  source env.sh
  if ! ./deploy_logging_stack.sh ; then
    log "Failed to deploy logging stack, exiting..."
    exit 1
  fi
}


run_workload() {
  timestamp="$(date "+%d-%m-%YT%H:%M:%S")"
  export CLUSTER_ID="$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)"
  mkdir -p temp
  log "Customizing log-generator CR file"
  envsubst < files/log_generator.yaml > temp/log_generator_"${timestamp}".yaml
  # Get bearer token and ES url if applicable
  if [[ "${CUSTOM_ES_URL}" == "" ]]; then
    ES_BACKEND_TOKEN="$(oc create token elasticsearch -n openshift-logging --duration 24h)"
    ES_BACKEND_URL="$(oc get route elasticsearch -n openshift-logging -o "jsonpath={.spec.host}")"
  else
    ES_BACKEND_URL="${CUSTOM_ES_URL}"
  fi

  # Add all viable options to the yaml
  if [[ "${ES_BACKEND_URL}" != "" ]]; then
    echo "      es_url: https://${ES_BACKEND_URL}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${ES_BACKEND_TOKEN}" != "" ]]; then
    echo "      es_token: ${ES_BACKEND_TOKEN}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${ES_BACKEND_INDEX}" != "" ]]; then
    echo "      es_index: ${ES_BACKEND_INDEX}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${CLOUDWATCH_LOG_GROUP}" != "" ]]; then
    echo "      cloudwatch_log_group: ${CLOUDWATCH_LOG_GROUP}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${AWS_REGION}" != "" ]]; then
    echo "      aws_region: ${AWS_REGION}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${AWS_ACCESS_KEY}" != "" ]]; then
    echo "      aws_access_key: ${AWS_ACCESS_KEY}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${AWS_SECRET_KEY}" != "" ]]; then
    echo "      aws_secret_key: ${AWS_SECRET_KEY}" >> temp/log_generator_"${timestamp}".yaml
  fi
  if [[ "${NODE_SELECTOR_KEY}" != "" ]] && [[ "${NODE_SELECTOR_VALUE}" != "" ]]; then
    echo "      label:" >> temp/log_generator_"${timestamp}".yaml
    echo "        key: ${NODE_SELECTOR_KEY}" >> temp/log_generator_"${timestamp}".yaml
    echo "        value: ${NODE_SELECTOR_VALUE}" >> temp/log_generator_"${timestamp}".yaml
  fi

  run_benchmark temp/log_generator_"${timestamp}".yaml "${TEST_TIMEOUT}"
  local rc=$?
  if [[ "${TEST_CLEANUP}" == "true" ]]; then
    log "Cleaning up benchmark"
    kubectl delete -f "${TMPCR}"
  fi
  return "${rc}"
}
