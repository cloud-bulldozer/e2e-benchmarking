#!/bin/bash -e

set -e

ES_SERVER=${ES_SERVER=https://USER:PASSWORD@HOSTNAME:443}
LOG_LEVEL=${LOG_LEVEL:-info}
if [ "$WORKERS_SCALE_VERSION" = "default" ]; then
    unset WORKERS_SCALE_VERSION
fi
WORKERS_SCALE_VERSION=${WORKERS_SCALE_VERSION:-0.0.1}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
UUID=${UUID:-$(uuidgen)}
WORKERS_SCALE_DIR=${WORKERS_SCALE_DIR:-/tmp}

download_binary(){
  WORKERS_SCALE_URL="https://github.com/cloud-bulldozer/workers-scale/releases/download/v${WORKERS_SCALE_VERSION}/workers-scale-V${WORKERS_SCALE_VERSION}-linux-x86_64.tar.gz"
  curl --fail --retry 8 --retry-all-errors -sS -L "${WORKERS_SCALE_URL}" | tar -xzC "${WORKERS_SCALE_DIR}/" workers-scale
}

download_binary
if [[ "$START_TIME" != 0 && "$END_TIME" != 0 ]]; then
  JOB_START=$(date -u -d "@$START_TIME" +"%Y-%m-%dT%H:%M:%SZ")
  JOB_END=$(date -u -d "@$END_TIME" +"%Y-%m-%dT%H:%M:%SZ")
fi
cmd="${WORKERS_SCALE_DIR}/workers-scale --uuid=${UUID} --start=$START_TIME --end=$END_TIME --log-level ${LOG_LEVEL} --gc=${GC}"
cmd+=" ${EXTRA_FLAGS}"

# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/ripsaw-kube-burner/_doc -d "${METADATA}" -o /dev/null
  cmd+=" --es-server=${ES_SERVER} --es-index=ripsaw-kube-burner"
fi
# Capture the exit code of the run, but don't exit the script if it fails.
set +e

echo $cmd
JOB_START=${JOB_START:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
$cmd
exit_code=$?
JOB_END=${JOB_END:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
if [ $exit_code -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" WORKLOAD="workers-scale" ES_SERVER="$ES_SERVER" ../../utils/index.sh
exit $exit_code
