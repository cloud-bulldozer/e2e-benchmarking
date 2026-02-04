#!/usr/bin/env bash
set -e

source ./env.sh
source ../../utils/common.sh

# Download k8s-netperf function
download_netperf() {
  echo $1
  curl --fail --retry 8 --retry-all-errors -sS -L ${NETPERF_URL} | tar -xz
}

# Download and extract k8s-netperf if we haven't already
if [ -f "${NETPERF_FILENAME}" ]; then
  cmd_version=$(./${NETPERF_FILENAME} --version | awk '/^Version:/{print $2}')
  if [[ "${NETPERF_VERSION}" == *"${cmd_version}"* ]]; then
    echo "We already have the specified version available."
  else
    download_netperf "Switching k8s-netperf version."
  fi
else
  download_netperf "Downloading k8s-netperf."
fi

log "###############################################"
log "Workload: ${WORKLOAD}"
log "UUID: ${UUID}"
log "###############################################"

# Capture exit code of k8s-netperf
set +e

JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize the command var
cmd="timeout ${TEST_TIMEOUT} ./k8s-netperf"

# Function to add flags conditionally
add_flag() {
  local flag_name="$1"
  local flag_value="$2"
  if [ -n "$flag_value" ]; then
    cmd+=" --$flag_name=$flag_value"
  fi
}

if [ -n "${EXTERNAL_SERVER_ADDRESS}" ]; then
  echo "EXTERNAL_SERVER_ADDRESS is set ${EXTERNAL_SERVER_ADDRESS}"
  add_flag "serverIP" "${EXTERNAL_SERVER_ADDRESS}"
fi

if [ "${LOCAL}" = "true" ]; then
  echo "LOCAL mode enabled — removing infra label from worker nodes"
  for node in $(oc get nodes -l node-role.kubernetes.io/infra -o name); do
    oc label "$node" node-role.kubernetes.io/infra- || true
  done
else
  echo "Labeling client and server nodes for consistency"
  WORKERS=$(kubectl get nodes -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!= --no-headers  | awk '{print $1}')
  CLIENT_NODE=$(echo "$WORKERS" | head -1)
  SERVER_NODE=$(echo "$WORKERS" | sed -n '2p')
  if [ -z "$CLIENT_NODE" ] || [ -z "$SERVER_NODE" ]; then
    echo "Error: Need at least 2 non-infra worker nodes"
    exit 1
  fi
  kubectl label nodes "$CLIENT_NODE" netperf=client --overwrite
  kubectl label nodes "$SERVER_NODE" netperf=server --overwrite
fi

# Add flags based on conditions
[ ! ${LOCAL} = true ] && add_flag "all" "${ALL_SCENARIOS}" || echo "LOCAL=true, not setting --all"
add_flag "clean" "${CLEAN_UP}"
add_flag "config" "${WORKLOAD}"
add_flag "debug" "${DEBUG}"
add_flag "local" "${LOCAL}"
add_flag "metrics" "${METRICS}"
add_flag "prom" "${PROMETHEUS_URL}"
add_flag "search" "${ES_SERVER}"
add_flag "tcp-tolerance" "${TOLERANCE}"
add_flag "uuid" "${UUID}"
add_flag "vm" "${VM}"
add_flag "pod" "${POD}"
add_flag "udnl2" "${UDNL2}"
add_flag "udnl3" "${UDNL3}"

# Execute the constructed command
echo "Executing command: $cmd"
eval "$cmd"
run=$?
echo "Removing client/server labels"
kubectl label nodes -l netperf=client netperf-
kubectl label nodes -l netperf=server netperf-
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Add debugging info (will be captured in each execution output)
echo "============ Debug Info ============"
echo k8s-netperf version ${NETPERF_VERSION}
oc get pods -n netperf -o wide
oc describe pods -n netperf
oc get nodes -o wide
oc get machineset -A || true

log "Finished workload ${0} ${WORKLOAD}, exit code ($run)"

cat *.csv
if [ $run -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="${JOB_START}" JOB_END="${JOB_END}" JOB_STATUS="${JOB_STATUS}" UUID="${UUID}" WORKLOAD="${WORKLOAD_NAME}" ES_SERVER="${ES_SERVER}" ../../utils/index.sh
exit $run
