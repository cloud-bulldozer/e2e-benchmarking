#!/usr/bin/env bash

## ROSA input vars
export AWS_REGION=${AWS_REGION:-us-west-2}
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export ROSA_ENVIRONMENT=${ROSA_ENVIRONMENT:-staging}
export ROSA_TOKEN=""
export PULL_SECRET=""

# Hosted clusters 
export NUMBER_OF_HOSTED_CLUSTER=${NUMBER_OF_HOSTED_CLUSTER:-2}
export COMPUTE_WORKERS_NUMBER=${COMPUTE_WORKERS_NUMBER:-24}

# Hosted cluster spec
export HYPERSHIFT_OPERATOR_VERSION="quay.io/hypershift/hypershift-operator:latest"
export RELEASE_IMAGE=""
export CPO_IMAGE=""
export NETWORK_TYPE=${NETWORK_TYPE:-OpenShiftSDN}
export REPLICA_TYPE=${REPLICA_TYPE:-HighlyAvailable}
export COMPUTE_WORKERS_TYPE=${COMPUTE_WORKERS_TYPE:-m5.4xlarge}

# Environment specifics
export HYPERSHIFT_CLI_INSTALL="true"
export HYPERSHIFT_CLI_VERSION="master"
export HYPERSHIFT_CLI_FORK="https://github.com/openshift/hypershift"

# Indexing stats
export ENABLE_INDEX=${ENABLE_INDEX:-true}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-ripsaw-kube-burner}
export THANOS_QUERIER_URL=${THANOS_QUERIER_URL:-http://thanos.apps.cluster.devcluster/api/v1/receive}
