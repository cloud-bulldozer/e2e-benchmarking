# Common
export UUID=${UUID:-$(uuidgen)}
export CLEAN_UP=${CLEAN_UP:-true}
export LOCAL=${LOCAL:-false}

# k8s-netperf version
if [ "${NETPERF_VERSION}" = "default" ]; then
    unset NETPERF_VERSION
fi
export ALL_SCENARIOS=${ALL_SCENARIOS:-true}
export DEBUG=${DEBUG:-true}
export METRICS=${METRICS:-true}
export VM=${VIRT:-false}
export UDNL2=${UDNL2:-false}
#export UDNL3=${UDNL3:-false}
export NETPERF_FILENAME=${NETPERF_FILENAME:-k8s-netperf}
export NETPERF_VERSION=${NETPERF_VERSION:-v0.1.28}
export OS=${OS:-Linux}
export PROMETHEUS_URL=
export ARCH=$(uname -m)
export NETPERF_URL=${NETPERF_URL:-https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz}

# External server
export EXTERNAL_SERVER_ADDRESS=${EXTERNAL_SERVER_ADDRESS:-}

# Workload
export WORKLOAD=${WORKLOAD:-smoke.yaml}
export TEST_TIMEOUT=${TEST_TIMEOUT:-14400}

# Tolerance of delta from hostNetwork to podNetwork - single stream
# Setting high watermark to only alert us if something has really gone
# sideways. We will be actively montiroing the results. Eventually
# we will have a better way to determine pass/fail via querying ES for
# historical data to do the comparison.
export TOLERANCE=${TOLERANCE:-70}
