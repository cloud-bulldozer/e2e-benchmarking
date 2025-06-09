#!/usr/bin/env bash

## ROSA input vars
export AWS_REGION=${AWS_REGION:-us-west-2}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-""}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-""}
export ROSA_ENVIRONMENT=${ROSA_ENVIRONMENT:-staging}
export ROSA_TOKEN=${ROSA_TOKEN:-""}
export PULL_SECRET=${PULL_SECRET:-""}

# Hosted clusters 
export NUMBER_OF_HOSTED_CLUSTER=${NUMBER_OF_HOSTED_CLUSTER:-2}
export COMPUTE_WORKERS_NUMBER=${COMPUTE_WORKERS_NUMBER:-1}

# Hosted cluster spec
export HYPERSHIFT_OPERATOR_IMAGE=${HYPERSHIFT_OPERATOR_IMAGE:-"quay.io/hypershift/hypershift-operator:latest"}
export RELEASE_IMAGE=${RELEASE_IMAGE:-""}
export CPO_IMAGE=${CPO_IMAGE:-""}
export NETWORK_TYPE=${NETWORK_TYPE:-OpenShiftSDN}
export CONTROLPLANE_REPLICA_TYPE=${CONTROLPLANE_REPLICA_TYPE:-HighlyAvailable}
export INFRA_REPLICA_TYPE=${INFRA_REPLICA_TYPE:-HighlyAvailable}
export COMPUTE_WORKERS_TYPE=${COMPUTE_WORKERS_TYPE:-m5.4xlarge}

# Environment specifics
export HYPERSHIFT_CLI_INSTALL=${HYPERSHIFT_CLI_INSTALL:-"true"}
export HYPERSHIFT_CLI_VERSION=${HYPERSHIFT_CLI_VERSION:-"main"}
export HYPERSHIFT_CLI_FORK=${HYPERSHIFT_CLI_FORK:-"https://github.com/openshift/hypershift"}
export HCP_PLATFORM_MONITORING=${HCP_PLATFORM_MONITORING:-"false"}
export HC_EXTERNAL_DNS=${HC_EXTERNAL_DNS:-"true"}
export HC_MULTI_AZ=${HC_MULTI_AZ:-"true"}

# Indexing stats
export ENABLE_INDEX=${ENABLE_INDEX:-true}
export ES_INDEX=${ES_INDEX:-ripsaw-kube-burner}
export THANOS_QUERIER_URL=${THANOS_QUERIER_URL:-http://thanos.apps.cluster.devcluster/api/v1/receive}
