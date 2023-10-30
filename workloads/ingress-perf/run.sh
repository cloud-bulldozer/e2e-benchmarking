#!/bin/bash -e

set -e

UUID=${UUID:-$(uuidgen)}
ES_SERVER=${ES_SERVER=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
ES_INDEX=${ES_INDEX:-ingress-performance}
WORKLOAD=${WORKLOAD:-ingress-perf}
LOG_LEVEL=${LOG_LEVEL:-info}
VERSION=${VERSION:-0.3.5}
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
cmd="./ingress-perf run --cfg ${CONFIG} --loglevel=${LOG_LEVEL} --uuid ${UUID}"
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=${ES_INDEX}"
fi
if [[ -n ${BASELINE_UUID} ]]; then
  cmd+=" --baseline-uuid=${BASELINE_UUID} --baseline-index=${BASELINE_INDEX} --tolerancy=${TOLERANCY}"
fi

# Do not exit if ingress-perf fails, we need to capture the exit code.
set +e

echo $cmd
JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
$cmd
exit_code=$?
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ $exit_code -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" ../../utils/index.sh
exit $exit_code
