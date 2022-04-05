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
export NETWORK_TYPE=${NETWORK_TYPE:-OpenshiftSDN}
export REPLICA_TYPE=${REPLICA_TYPE:-HighlyAvailable}
export COMPUTE_WORKERS_TYPE=${COMPUTE_WORKERS_TYPE:-m5.4xlarge}
