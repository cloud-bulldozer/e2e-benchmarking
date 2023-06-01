#!/bin/bash

# UUID
export UUID=${UUID:-`uuidgen`}

# Benchmark-operator
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export METADATA_COLLECTION=${METADATA_COLLECTION:-false}

# Logging workload args
export MESSAGE_SIZE=${MESSAGE_SIZE:-512}
export DURATION=${DURATION:-1}
export MESSAGES_PER_SECOND=${MESSAGES_PER_SECOND:-0}
export POD_COUNT=${POD_COUNT:-1}
export TIMEOUT=${TIMEOUT:-600}
export DEBUG=${DEBUG:-false}

# ES backend information
export ES_BACKEND_URL=${ES_BACKEND_URL:-""}
export ES_BACKEND_INDEX=${ES_BACKEND_INDEX:-""}
export ES_BACKEND_TOKEN=${ES_BACKEND_TOKEN:-""}

# AWS CloudWatch backend information
export CLOUDWATCH_LOG_GROUP=${CLOUDWATCH_LOG_GROUP:-""}
export AWS_REGION=${AWS_REGION:-""}
export AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-""}
export AWS_SECRET_KEY=${AWS_SECRET_KEY:-""}

# Test Pods Node Selector
export NODE_SELECTOR_KEY=${NODE_SELECTOR_KEY:-""}
export NODE_SELECTOR_VALUE=${NODE_SELECTOR_VALUE:-""}

# Deploy Logging
export DEPLOY_LOGGING=${DEPLOY_LOGGING:-true}

# Cleanup benchmark when done
export TEST_CLEANUP=${TEST_CLEANUP:-"false"}

# Deploy Variables
export CHANNEL=${CHANNEL:="stable-5.6"}
export CUSTOM_ES_URL=${CUSTOM_ES_URL:=""}
export ES_NODE_COUNT=${ES_NODE_COUNT:=3}
export ES_STORAGE_CLASS=${ES_STORAGE_CLASS:="gp3-csi"}
export ES_STORAGE_SIZE=${ES_STORAGE_SIZE:="100G"}
export ES_MEMORY_LIMITS=${ES_MEMORY_LIMITS:="16Gi"}
export ES_MEMORY_REQUESTS=${ES_MEMORY_REQUESTS:="16Gi"}
export ES_PROXY_MEMORY_LIMITS=${ES_PROXY_MEMORY_LIMITS:="256Mi"}
export ES_PROXY_MEMORY_REQUESTS=${ES_PROXY_MEMORY_REQUESTS:="256Mi"}
export ES_REDUNDANCY_POLICY=${ES_REDUNDANCY_POLICY:="SingleRedundancy"}
export FLUENTD_MEMORY_LIMITS=${FLUENTD_MEMORY_LIMITS:="1Gi"}
export FLUENTD_CPU_REQUESTS=${FLUENTD_CPU_REQUESTS:="500m"}
export FLUENTD_MEMORY_REQUESTS=${FLUENTD_MEMORY_REQUESTS:="1Gi"}
export FORWARD_LOGS=${FORWARD_LOGS:="[application]"}
TEST_CLEANUP=${TEST_CLEANUP:-true}
export TEST_TIMEOUT=${TEST_TIMEOUT:-7200}
