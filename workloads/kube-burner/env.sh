
# Common
export QPS=10
export Burst=10
export ES_SERVER=https://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
export ES_PORT=443
export ES_INDEX=ripsaw-kube-burner
export PROM_URL=https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091
export JOB_TIMEOUT=7200
export WORKLOAD_NODE=""
export CERBERUS_URL=""
export STEP_SIZE=30s
export METRICS_PROFILE=metrics.yaml

# Cluster density specific
export JOB_ITERATIONS=1000

# Kubelet-density and kubelet-density-heavy specific
export NODE_COUNT=4
export PODS_PER_NODE=250

# ES password
export ES_USER=""
export ES_PASSWORD=""
