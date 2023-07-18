# Common
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}

# k8s-netperf version
export NETPERF_VERSION=${VERSION:-v0.1.12}
export OS=${OS:-Linux}
export ARCH=$(arch)
export NETPERF_URL=${NETPERF_URL:-https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz}

# Workload
export WORKLOAD=${WORKLOAD:-smoke.yaml}
export TEST_TIMEOUT=${TEST_TIMEOUT:-7200}

# Tolerance of delta from hostNetwork to podNetwork - single stream
# Setting high watermark to only alert us if something has really gone
# sideways. We will be actively montiroing the results. Eventually
# we will have a better way to determine pass/fail via querying ES for
# historical data to do the comparison.
export TOLERANCE=${TOLERANCE:-70}
