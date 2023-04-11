# General
export KUBECONFIG=${KUBECONFIG:-~/.kube/config}
export UUID=${UUID:-$(uuidgen)}

# ES configuration
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-router-test-results}

# Environment setup
NUM_NODES=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!= --no-headers | grep -cw Ready)
LARGE_SCALE_THRESHOLD=${LARGE_SCALE_THRESHOLD:-24}
METADATA_COLLECTION=${METADATA_COLLECTION:-true}
KUBE_BURNER_RELEASE_URL=${KUBE_BURNER_RELEASE_URL:-https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.16.2/kube-burner-0.16.2-Linux-x86_64.tar.gz}
KUBE_BURNER_IMAGE=quay.io/cloud-bulldozer/kube-burner:latest
#HAPROXY_IMAGE="quay.io/cloud-bulldozer/openshift-router-perfscale:-haproxy-v2.2.20"
#INGRESS_OPERATOR_IMAGE="quay.io/cloud-bulldozer/openshift-cluster-ingress-operator:balance-random"
export TERMINATIONS=${TERMINATIONS:-"http edge passthrough reencrypt mix"}
export DEPLOYMENT_REPLICAS=${DEPLOYMENT_REPLICAS:-1}
#export SMALL_SCALE_ROUTES=10
#export LARGE_SCALE_ROUTES=50
export SERVICE_TYPE=${SERVICE_TYPE:-NodePort}
export NUMBER_OF_ROUTERS=${NUMBER_OF_ROUTERS:-2}
export HOST_NETWORK=${HOST_NETWORK:-true}
export NODE_SELECTOR=${NODE_SELECTOR:-'{node-role.kubernetes.io/workload: }'}

# Cluster information
export CLUSTER_ID=$(oc get clusterversion -o jsonpath='{.items[].spec.clusterID}')
export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
export OPENSHIFT_VERSION=$(oc version -o json |  jq -r '.openshiftVersion')
KUBERNETES_MAJOR_VERSION=$(oc version -o json |  jq -r '.serverVersion.major')
KUBERNETES_MINOR_VERSION=$(oc version -o json |  jq -r '.serverVersion.minor')
export KUBERNETES_VERSION=${KUBERNETES_MAJOR_VERSION}.${KUBERNETES_MINOR_VERSION}
export CLUSTER_NETWORK_TYPE=$(oc get network.config/cluster -o jsonpath='{.spec.networkType}')
export NETWORK_TYPE=$CLUSTER_NETWORK_TYPE
export PLATFORM_STATUS=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus}')
export HYPERSHIFT_MANAGEMENT_KUBECONFIG=${HYPERSHIFT_MANAGEMENT_KUBECONFIG:-""}
export RESCHEDULE_MONITORING_STACK=${RESCHEDULE_MONITORING_STACK:-true}

# Benchmark configuration
RUNTIME=${RUNTIME:-60}
TLS_REUSE=${TLS_REUSE:-true}
URL_PATH=${URL_PATH:-/1024.html}
SAMPLES=${SAMPLES:-2}
QUIET_PERIOD=${QUIET_PERIOD:-60s}
KEEPALIVE_REQUESTS=${KEEPALIVE_REQUESTS:-"0 1 50"}

# Comparison and csv generation
BASELINE_UUID=${BASELINE_UUID}
ES_SERVER_BASELINE=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
COMPARISON_CONFIG=${COMPARISON_CONFIG:-"mb-touchstone.json"}
COMPARISON_RC=${COMPARISON_RC:-0}
GEN_CSV=${GEN_CSV:-false}
if [[ -v TOLERANCY_RULES_CFG ]]; then
  TOLERANCY_RULES=${TOLERANCY_RULES_CFG}
else
  TOLERANCY_RULES=${PWD}/mb-tolerancy-rules.yaml
fi
if [[ -v COMPARISON_OUTPUT_CFG ]]; then
  COMPARISON_OUTPUT=${COMPARISON_OUTPUT_CFG}
else
  COMPARISON_OUTPUT=${PWD}/ingress-performance-${UUID}.csv
fi

GSHEET_KEY_LOCATION=${GSHEET_KEY_LOCATION}
EMAIL_ID_FOR_RESULTS_SHEET=${EMAIL_ID_FOR_RESULTS_SHEET}
export SORT_BY_VALUE=${SORT_BY_VALUE:-false}
