# General
export KUBECONFIG=${KUBECONFIG:-~/.kube/config}
export UUID=$(uuidgen)

# ES configuration
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-router-test-results}
export ES_SERVER_BASELINE=""

# Gold comparison
COMPARE_WITH_GOLD=${COMPARE_WITH_GOLD:-false}
ES_GOLD=${ES_GOLD:-${ES_SERVER}}
GOLD_SDN=${GOLD_SDN:-openshiftsdn}
GOLD_OCP_VERSION=${GOLD_OCP_VERSION}

# Environment setup
NUM_NODES=$(oc get node -l node-role.kubernetes.io/worker --no-headers | grep -cw Ready)
ENGINE=${ENGINE:-podman}
KUBE_BURNER_RELEASE_URL=${KUBE_BURNER_RELEASE_URL:-https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.11/kube-burner-0.11-Linux-x86_64.tar.gz}
KUBE_BURNER_IMAGE=quay.io/cloud-bulldozer/kube-burner:latest
TERMINATIONS=${TERMINATIONS:-"http edge passthrough reencrypt mix"}
INFRA_TEMPLATE=http-perf.yml.tmpl
INFRA_CONFIG=http-perf.yml
export SERVICE_TYPE=${SERVICE_TYPE:-NodePort}
export NUMBER_OF_ROUTERS=${NUMBER_OF_ROUTERS:-2}
export HOST_NETWORK=${HOST_NETWORK:-true}
export NODE_SELECTOR=${NODE_SELECTOR:-'{node-role.kubernetes.io/workload: }'}

# Benchmark configuration
RUNTIME=${RUNTIME:-60}
TLS_REUSE=${TLS_REUSE:-true}
URL_PATH=${URL_PATH:-/1024.html}
SAMPLES=${SAMPLES:-2}
QUIET_PERIOD=${QUIET_PERIOD:-60s}
KEEPALIVE_REQUESTS=${KEEPALIVE_REQUESTS:-"0 1 50"}

# Comparison and csv generation
export COMPARE="false"
THROUGHPUT_TOLERANCE=${THROUGHPUT_TOLERANCE:-5}
LATENCY_TOLERANCE=${LATENCY_TOLERANCE:-5}
PREFIX=${PREFIX:-$(oc get clusterversion version -o jsonpath="{.status.desired.version}")}
LARGE_SCALE_THRESHOLD=${LARGE_SCALE_THRESHOLD:-24}
METADATA_COLLECTION=${METADATA_COLLECTION:-true}
SMALL_SCALE_BASELINE_UUID=${SMALL_SCALE_BASELINE_UUID}
LARGE_SCALE_BASELINE_UUID=${LARGE_SCALE_BASELINE_UUID}
export GSHEET_KEY_LOCATION=${GSHEET_KEY_LOCATION}
export EMAIL_ID_FOR_RESULTS_SHEET=${EMAIL_ID_FOR_RESULTS_SHEET}
