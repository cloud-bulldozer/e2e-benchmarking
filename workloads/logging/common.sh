#!/usr/bin/env bash
source env.sh
source ../../utils/benchmark-operator.sh

# Logging format
log() {
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}

# Check if oc client is installed
log "Checking if oc client is installed"

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    log "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi


deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
  rm -rf benchmark-operator
  git clone --single-branch --branch ${OPERATOR_BRANCH} ${OPERATOR_REPO} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
}

deploy_logging_stack() {
  log "Deploying logging stack"
  source env.sh
  ./deploy_logging_stack.sh
}

run_workload() {
  timestamp=`date "+%d-%m-%YT%H:%M:%S"`
  log "Customizing log-generator CR file"
  envsubst < files/log_generator.yaml > log_generator_$timestamp.yaml
  if [[ ${DEPLOY_LOGGING} == "true" ]]; then
    # Get bearer token and ES url if applicable
    if [[ ${CUSTOM_ES_URL} == "" ]]; then
      ES_BACKEND_TOKEN=`oc whoami -t`
      ES_BACKEND_URL=`oc get route elasticsearch -n openshift-logging -o jsonpath={.spec.host}`
    else
      ES_BACKEND_URL=$CUSTOM_ES_URL
    fi
  fi

  # Add all viable options to the yaml
  if [[ ${ES_BACKEND_URL} != "" ]]; then
    echo "    es_url: "$ES_BACKEND_URL >> log_generator_$timestamp.yaml
  fi
  if [[ ${ES_BACKEND_TOKEN} != "" ]]; then
    echo "    es_token: "$ES_BACKEND_TOKEN >> log_generator_$timestamp.yaml
  fi
  if [[ ${ES_BACKEND_INDEX} != "" ]]; then
    echo "    es_index: "$ES_BACKEND_INDEX >> log_generator_$timestamp.yaml
  fi
  if [[ ${ES_BACKEND_INDEX} != "" ]]; then
    echo "    es_index: "$ES_BACKEND_INDEX >> log_generator_$timestamp.yaml
  fi
  if [[ ${CLOUDWATCH_LOG_GROUP} != "" ]]; then
    echo "    cloudwatch_log_group: "$CLOUDWATCH_LOG_GROUP >> log_generator_$timestamp.yaml
  fi
  if [[ ${AWS_REGION} != "" ]]; then
    echo "    aws_region: "$AWS_REGION >> log_generator_$timestamp.yaml
  fi
  if [[ ${AWS_ACCESS_KEY} != "" ]]; then
    echo "    aws_access_key: "$AWS_ACCESS_KEY >> log_generator_$timestamp.yaml
  fi
  if [[ ${AWS_SECRET_KEY} != "" ]]; then
    echo "    aws_secret_key: "$AWS_SECRET_KEY >> log_generator_$timestamp.yaml
  fi
  if [[ ${NODE_SELECTOR_KEY} != "" ]]; then
    echo "    label:" >> log_generator_$timestamp.yaml
    echo "      key: " >> log_generator_$timestamp.yaml
    echo "      value: " >> log_generator_$timestamp.yaml
  fi

  run_benchmark log_generator_$timestamp.yaml ${TEST_TIMEOUT}
  local rc=$?
  if [[ ${TEST_CLEANUP} == "true" ]]; then
    log "Cleaning up benchmark"
    kubectl delete -f ${TMPCR}
  fi
  return ${rc}
}
