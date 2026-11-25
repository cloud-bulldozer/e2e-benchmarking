# shellcheck shell=bash
# Common
export UUID=${UUID:-$(uuidgen)}
export CLEAN_UP=${CLEAN_UP:-true}
export PLATFORM=${PLATFORM:-openshift}

# Cross-cluster mode: client pods on the KUBECONFIG cluster, server pods on the
# SERVER_KUBECONFIG cluster. A non-empty SERVER_KUBECONFIG turns it on.
export SERVER_KUBECONFIG=${SERVER_KUBECONFIG:-}
export SERVER_DOMAIN=${SERVER_DOMAIN:-}
export SERVER_PROMETHEUS_URL=${SERVER_PROMETHEUS_URL:-}

if [[ "${PLATFORM}" == "microshift" ]]; then
    # Same node by default; a cross-cluster run places client and server on
    # different clusters, so LOCAL defaults to false there.
    if [[ -n "${SERVER_KUBECONFIG}" ]]; then
        export LOCAL=${LOCAL:-false}
    else
        export LOCAL=${LOCAL:-true}
    fi
    # MicroShift has no in-cluster Prometheus; opt out by default so a
    # default run does not fail the PROMETHEUS_URL guard in run.sh.
    export METRICS=${METRICS:-false}
else
    export LOCAL=${LOCAL:-false}
    export METRICS=${METRICS:-true}
fi

# k8s-netperf version
if [ "${NETPERF_VERSION}" = "default" ]; then
    unset NETPERF_VERSION
fi
export ALL_SCENARIOS=${ALL_SCENARIOS:-true}
export DEBUG=${DEBUG:-true}
export VM=${VM:-false}
export POD=${POD:-true}
export UDNL2=${UDNL2:-false}
export UDNL3=${UDNL3:-false}
export BRIDGE=${BRIDGE:-}
export BRIDGE_CONFIG=${BRIDGE_CONFIG:-}
export LOCALNET=${LOCALNET:-}
export LOCALNET_CONFIG=${LOCALNET_CONFIG:-}
export NETPERF_FILENAME=${NETPERF_FILENAME:-k8s-netperf}
export NETPERF_VERSION=${NETPERF_VERSION:-v0.1.43}
export OS=${OS:-Linux}
export PROMETHEUS_URL=${PROMETHEUS_URL:-}
ARCH=$(uname -m)
export ARCH
export NETPERF_URL=${NETPERF_URL:-https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz}

# External server
export EXTERNAL_SERVER_ADDRESS=${EXTERNAL_SERVER_ADDRESS:-}

# Workload
export WORKLOAD=${WORKLOAD:-smoke.yaml}
export WORKLOAD_NAME=${WORKLOAD_NAME:-k8s-netperf}
export TEST_TIMEOUT=${TEST_TIMEOUT:-14400}

# Deadlines (GNU timeout durations, greater than zero). See README for the
# worst-case run time they give.
# Grace after TEST_TIMEOUT or a stop signal before k8s-netperf is killed: covers
# the cross-cluster cleanup of k8s-netperf after SIGTERM (30 s + 330 s + 300 s).
export TEST_KILL_AFTER=${TEST_KILL_AFTER:-660}
# Download and extraction of k8s-netperf, retries included.
export DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT:-600}
# Each oc / kubectl call (also inside utils/index.sh) and the version probe.
export CALL_TIMEOUT=${CALL_TIMEOUT:-60}
# utils/index.sh as a whole.
export INDEX_TIMEOUT=${INDEX_TIMEOUT:-300}

# Tolerance of delta from hostNetwork to podNetwork - single stream
# Setting high watermark to only alert us if something has really gone
# sideways. We will be actively montiroing the results. Eventually
# we will have a better way to determine pass/fail via querying ES for
# historical data to do the comparison.
export TOLERANCE=${TOLERANCE:-70}
