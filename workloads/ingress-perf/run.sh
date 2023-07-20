#!/bin/bash -e

set -e

ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
ES_INDEX=${ES_INDEX:-ingress-performance}
LOG_LEVEL=${LOG_LEVEL:-info}
VERSION=${VERSION:-0.2.4}
CONFIG=${CONFIG:?}
BASELINE_UUID=${BASELINE_UUID:-}
BASELINE_INDEX=${BASELINE_INDEX:-ingress-performance-baseline}
TOLERANCY=${TOLERANCY:-20}
OS=$(uname -s)
HARDWARE=$(uname -m)

download_binary(){
  INGRESS_PERF_URL=https://github.com/cloud-bulldozer/ingress-perf/releases/download/v${VERSION}/ingress-perf-${OS}-v${VERSION}-${HARDWARE}.tar.gz
  curl -sS -L ${INGRESS_PERF_URL} | tar xz ingress-perf
}

download_binary
cmd="./ingress-perf run --cfg ${CONFIG} --loglevel=${LOG_LEVEL}"
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=${ES_INDEX}"
fi
if [[ -n ${BASELINE_UUID} ]]; then
  cmd+=" --baseline-uuid=${BASELINE_UUID} --baseline-index=${BASELINE_INDEX} --tolerancy=${TOLERANCY}"
fi
echo $cmd
exec $cmd
