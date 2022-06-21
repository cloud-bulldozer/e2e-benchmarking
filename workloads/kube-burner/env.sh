#!/usr/bin/env bash

# Benchmark-operator
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
export WAIT_WHEN_FINISHED=true
export POD_WAIT=${POD_WAIT:-false}
export WAIT_FOR=${WAIT_FOR:-[]}
export VERIFY_OBJECTS=${VERIFY_OBJECTS:-true}
export ERROR_ON_VERIFY=${ERROR_ON_VERIFY:-true}
export PRELOAD_IMAGES=${PRELOAD_IMAGES:-true}
export PRELOAD_PERIOD=${PRELOAD_PERIOD:-2m}

# Kube-burner job
export KUBE_BURNER_IMAGE=${KUBE_BURNER_IMAGE:-quay.io/cloud-bulldozer/kube-burner:v0.16}
export NODE_SELECTOR=${NODE_SELECTOR:-'{node-role.kubernetes.io/worker: }'}
export JOB_TIMEOUT=${JOB_TIMEOUT:-14400}
export LOG_STREAMING=${LOG_STREAMING:-true}
export METRICS_PROFILE=${METRICS_PROFILE}

# Misc
export CLEANUP_WHEN_FINISH=${CLEANUP_WHEN_FINISH:-false}
export CLEANUP_TIMEOUT=${CLEANUP_TIMEOUT:-30m}
export LOG_LEVEL=${LOG_LEVEL:-info}

# Pprof
export PPROF_COLLECTION=${PPROF_COLLECTION:-false}
export PPROF_COLLECTION_INTERVAL=${PPROF_COLLECTION_INTERVAL:-5m}

# Hypershift vars
export HYPERSHIFT=${HYPERSHIFT:-false}
export MGMT_CLUSTER_NAME=${MGMT_CLUSTER_NAME:-perf-management-cluster}
export HOSTED_CLUSTER_NS=${HOSTED_CLUSTER_NS:-clusters-perf-hosted-1}
export THANOS_RECEIVER_URL=${THANOS_RECEIVER_URL:-http://thanos.apps.cluster.devcluster/api/v1/receive}

# # Concurrent Builds variables
# Space seperated list of build numbers and build app types
export BUILD_LIST=${BUILD_LIST:-"1 8 15 30 45 60 75"}
export APP_LIST=${APP_LIST:-'cakephp eap django nodejs'}

# Concurrent Build Specific
export APP_SUBNAME=""
export APP=""
export BUILD_IMAGE_STREAM=""
export SOURCE_STRAT_ENV=""
export SOURCE_STRAT_FROM=""
export POST_COMMIT_SCRIPT=""
export SOURCE_STRAT_FROM_VERSION=""
export BUILD_IMAGE=""
export GIT_URL=""

# Thresholds
export POD_READY_THRESHOLD=${POD_READY_THRESHOLD:-5000ms}

# Alerting
export PLATFORM_ALERTS=${PLATFORM_ALERTS:-false}

# Output and Comparisons
export COMPARISON_CONFIG=${COMPARISON_CONFIG:-""}
export GSHEET_KEY_LOCATION=${GSHEET_KEY_LOCATION}
export EMAIL_ID_FOR_RESULTS_SHEET=${EMAIL_ID_FOR_RESULTS_SHEET}
GEN_CSV=${GEN_CSV:-false}
