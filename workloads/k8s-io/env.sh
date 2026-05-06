# Common
export UUID=${UUID:-$(uuidgen)}
export CLEANUP=${CLEANUP:-true}

# k8s-io version
if [ "${K8S_IO_VERSION}" = "default" ]; then
    unset K8S_IO_VERSION
fi
export K8S_IO_FILENAME=${K8S_IO_FILENAME:-k8s-io}
export K8S_IO_VERSION=${K8S_IO_VERSION:-v0.1.0}
export OS=${OS:-Linux}
export ARCH=$(uname -m)
export K8S_IO_URL=${K8S_IO_URL:-https://github.com/jtaleric/k8s-io/releases/download/${K8S_IO_VERSION}/k8s-io_${OS}_${K8S_IO_VERSION}_${ARCH}.tar.gz}

# Elasticsearch
export ES_SERVER=${ES_SERVER:-}
export ES_INDEX=${ES_INDEX:-ripsaw-fio}

# Workload
export CONFIG=${CONFIG:-smoke.yaml}
export WORKLOAD=${WORKLOAD:-k8s-io}
export TEST_TIMEOUT=${TEST_TIMEOUT:-14400}
