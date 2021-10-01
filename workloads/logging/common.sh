#!/usr/bin/env bash
source ../../utils/benchmark-operator.sh

set -x

# Logging format
log() {
  echo -e "\033[1m$(date "+%d-%m-%YT%H:%M:%S") ${@}\033[0m"
}

# Check if oc client is installed
log "Checking if oc client is installed"
which oc &>/dev/null
if [[ $? != 0 ]]; then
  log "Looks like oc client is not installed, please install before continuing"
  log "Exiting"
  exit 1
fi

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    log "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

# UUID
export UUID=${UUID:-`uuidgen`}

# Operator
operator_repo=${OPERATOR_REPO:-https://github.com/cloud-bulldozer/benchmark-operator.git}
operator_branch=${OPERATOR_BRANCH:-master}
timestamp=`date "+%d-%m-%YT%H:%M:%S"`
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export METADATA_COLLECTION=${METADATA_COLLECTION:-false}

# Logging workload args
export MESSAGE_SIZE=${MESSAGE_SIZE:-512}
export DURATION=${DURATION:-1}
export MESSAGES_PER_SECOND=${MESSAGES_PER_SECOND:-0}
export POD_COUNT=${POD_COUNT:-1}
export TIMEOUT=${TIMEOUT:-600}

# ES backend information
export ES_BACKEND_URL=${ES_BACKEND_URL:-""}
export ES_BACKEND_INDEX=${ES_BACKEND_INDEX:-""}
export ES_BACKEND_TOKEN=${ES_BACKEND_TOKEN:-""}

# AWS CloudWatch backend information
export CLOUDWATCH_LOG_GROUP=${CLOUDWATCH_LOG_GROUP:-""}
export AWS_REGION=${AWS_REGION:-""}
export AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-""}
export AWS_SECRET_KEY=${AWS_SECRET_KEY:-""}

# Node Selector
export NODE_SELECTOR_KEY=${NODE_SELECTOR_KEY:-""}
export NODE_SELECTOR_VALUE=${NODE_SELECTOR_VALUE:-""}

# Deploy Logging
export DEPLOY_LOGGING=${DEPLOY_LOGGING:-true}

# Overall test timeout in seconds (NOTE: this is different than the timeout for the benchmark)
export TEST_TIMEOUT=${TEST_TIMEOUT:-7200}

# Cleanup benchmark when done
export TEST_CLEANUP=${TEST_CLEANUP:-"false"}

deploy_operator() {
  deploy_benchmark_operator ${operator_repo} ${operator_branch}
  rm -rf benchmark-operator
  git clone --single-branch --branch ${operator_branch} ${operator_repo} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
}

deploy_logging_stack() {
  log "Deploying logging stack"
  source env.sh
  ./deploy_logging_stack.sh
}

run_workload() {
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

  run_benchmark log_generator_$timestamp.yaml 7200
}

cleanup() {
  log "Cleaning up benchmark"
  oc delete -f log_generator_$timestamp.yaml
}
