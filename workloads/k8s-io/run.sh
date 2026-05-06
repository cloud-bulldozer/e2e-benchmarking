#!/usr/bin/env bash
set -e

source ./env.sh
source ../../utils/common.sh

# Download k8s-io function
download_k8s_io() {
  echo $1
  curl --fail --retry 8 --retry-all-errors -sS -L ${K8S_IO_URL} | tar -xz ${K8S_IO_FILENAME}
}

# Download and extract k8s-io if we haven't already
if [ -f "${K8S_IO_FILENAME}" ]; then
  cmd_version=$(./${K8S_IO_FILENAME} --version | awk '/^Version:/{print $2}')
  if [[ "${K8S_IO_VERSION}" == *"${cmd_version}"* ]]; then
    echo "We already have the specified version available."
  else
    download_k8s_io "Switching k8s-io version."
  fi
else
  download_k8s_io "Downloading k8s-io."
fi

log "###############################################"
log "Workload: ${WORKLOAD}"
log "UUID: ${UUID}"
log "Config: ${CONFIG}"
log "###############################################"

# Capture exit code of k8s-io
set +e

JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cmd="timeout ${TEST_TIMEOUT} ./${K8S_IO_FILENAME} -config ${CONFIG}"

echo "Executing command: $cmd"
eval "$cmd"
run=$?

JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ "${CLEANUP}" = "true" ]; then
  echo "Cleaning up resources..."
  ./${K8S_IO_FILENAME} -config ${CONFIG} -cleanup
fi

log "Finished workload ${0} ${CONFIG}, exit code ($run)"

if [ $run -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="${JOB_START}" JOB_END="${JOB_END}" JOB_STATUS="${JOB_STATUS}" UUID="${UUID}" WORKLOAD="${WORKLOAD}" ES_SERVER="${ES_SERVER}" ../../utils/index.sh
exit $run
