#!/usr/bin/env bash

# Benchark-operator
export OPERATOR_REPO=${OPERATOR_REPO:-https://github.com/cloud-bulldozer/benchmark-operator.git}
export OPERATOR_BRANCH=${OPERATOR_BRANCH:-master}
export POD_READY_TIMEOUT=${POD_READY_TIMEOUT:-180}

# Indexing variables
export INDEXING=${INDEXING:-true}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-ripsaw-kube-burner}
export STEP_SIZE=${STEP_SIZE:-30s}
export METADATA_COLLECTION=${METADATA_COLLECTION:-true}
export PROM_URL=${PROM_URL:-https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091}

# Kube-burner vars
export QPS=${QPS:-20}
export BURST=${BURST:-20}
export MAX_WAIT_TIMEOUT=${MAX_WAIT_TIMEOUT:-1h}
export CLEANUP=${CLEANUP:-true}
export POD_NODE_SELECTOR=${POD_NODE_SELECTOR:-'{node-role.kubernetes.io/worker: }'}
export WAIT_WHEN_FINISHED=true
export POD_WAIT=${POD_WAIT:-false}
export WAIT_FOR=${WAIT_FOR:-[]}
export VERIFY_OBJECTS=${VERIFY_OBJECTS:-true}
export ERROR_ON_VERIFY=${ERROR_ON_VERIFY:-true}
export PRELOAD_IMAGES=${PRELOAD_IMAGES:-true}
export PRELOAD_PERIOD=${PRELOAD_PERIOD:-2m}

# Remote configuration
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE}
export REMOTE_ALERT_PROFILE=${REMOTE_ALERT_PROFILE}

# Kube-burner job
export KUBE_BURNER_IMAGE=${KUBE_BURNER_IMAGE:-quay.io/cloud-bulldozer/kube-burner:v0.15.3}
export NODE_SELECTOR=${NODE_SELECTOR:-'{node-role.kubernetes.io/worker: }'}
export JOB_TIMEOUT=${JOB_TIMEOUT:-14400}
export LOG_STREAMING=${LOG_STREAMING:-true}

# Misc
export CLEANUP_WHEN_FINISH=${CLEANUP_WHEN_FINISH:-false}
export LOG_LEVEL=${LOG_LEVEL:-info}

# Pprof
export PPROF_COLLECTION=${PPROF_COLLECTION:-false}
export PPROF_COLLECTION_INTERVAL=${PPROF_COLLECTION_INTERVAL:-5m}

# Hypershift vars
export HYPERSHIFT=${HYPERSHIFT:-false}
export MGMT_CLUSTER_NAME=${MGMT_CLUSTER_NAME:-perf-management-cluster}
export HOSTED_CLUSTER_NS=${HOSTED_CLUSTER_NS:-clusters-perf-hosted-1}
export THANOS_RECEIVER_URL=${THANOS_RECEIVER_URL:-http://thanos.apps.cluster.devcluster/api/v1/receive}

# Thresholds
export POD_READY_THRESHOLD=${POD_READY_THRESHOLD:-5000ms}

