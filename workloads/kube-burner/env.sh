# Benchark-operator
export OPERATOR_REPO=${OPERATOR_REPO:-https://github.com/cloud-bulldozer/benchmark-operator.git}
export OPERATOR_BRANCH=${OPERATOR_BRANCH:-master}

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
export POD_READY_TIMEOUT=${POD_READY_TIMEOUT:-1200}
export CLEANUP=${CLEANUP:-true}
export POD_NODE_SELECTOR=${POD_NODE_SELECTOR:-'{"node-role.kubernetes.io/worker": ""}'}
export WAIT_WHEN_FINISHED=true
export POD_WAIT=${POD_WAIT:-false}
export WAIT_FOR=${WAIT_FOR:-[]}
export VERIFY_OBJECTS=${VERIFY_OBJECTS:-true}
export ERROR_ON_VERIFY=${ERROR_ON_VERIFY:-true}
export JOB_ITERATIONS=${JOB_ITERATIONS:-1000}

# Remote configuration
export REMOTE_CONFIG=${REMOTE_CONFIG}
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE}
export REMOTE_ALERT_PROFILE=${REMOTE_ALERT_PROFILE}

# Kube-burner job
export NODE_SELECTOR=${NODE_SELECTOR:-'{"node-role.kubernetes.io/worker": ""}'}
export JOB_TIMEOUT=${JOB_TIMEOUT:-14400}
export LOG_STREAMING=${LOG_STREAMING:-true}

# Misc
export CLEANUP_WHEN_FINISH=${CLEANUP_WHEN_FINISH:-false}
export LOG_LEVEL=${LOG_LEVEL:-info}
