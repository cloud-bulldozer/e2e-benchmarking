#!/usr/bin/env bash
set -e

source ./env.sh
source ../../utils/common.sh

CROSS_CLUSTER=false
if [[ -n "${SERVER_KUBECONFIG}" ]]; then
  CROSS_CLUSTER=true
fi

# ---------------------------------------------------------------------------
# Input checks: they run before the download and before any cluster call.
# ---------------------------------------------------------------------------

input_error() {
  echo "ERROR: $*"
  exit 1
}

if [[ "${CROSS_CLUSTER}" == "true" ]]; then
  if [[ "${LOCAL}" == "true" ]]; then
    input_error "SERVER_KUBECONFIG (cross-cluster mode) cannot be combined with LOCAL=true"
  fi
  if [[ -n "${EXTERNAL_SERVER_ADDRESS}" ]]; then
    input_error "SERVER_KUBECONFIG (cross-cluster mode) cannot be combined with EXTERNAL_SERVER_ADDRESS"
  fi
  if [[ ! -f "${SERVER_KUBECONFIG}" || ! -r "${SERVER_KUBECONFIG}" ]]; then
    input_error "SERVER_KUBECONFIG=${SERVER_KUBECONFIG} is not a readable file"
  fi
elif [[ -n "${SERVER_DOMAIN}" || -n "${SERVER_PROMETHEUS_URL}" ]]; then
  input_error "SERVER_DOMAIN and SERVER_PROMETHEUS_URL need SERVER_KUBECONFIG (cross-cluster mode)"
fi

if [[ "${PLATFORM}" == "microshift" && "${LOCAL}" != "true" && "${CROSS_CLUSTER}" != "true" ]]; then
  input_error "PLATFORM=microshift requires LOCAL=true, or SERVER_KUBECONFIG for a cross-cluster run"
fi

if [[ "${PLATFORM}" == "microshift" && "${METRICS}" == "true" && -z "${PROMETHEUS_URL}" ]]; then
  input_error "PLATFORM=microshift with METRICS=true requires PROMETHEUS_URL"
fi

# Work files of this run (node state, label call output), removed on exit.
work_dir=$(mktemp -d) || input_error "cannot create a temporary directory"
trap 'rm -rf "${work_dir}"' EXIT

# ---------------------------------------------------------------------------
# k8s-netperf binary
# ---------------------------------------------------------------------------

# Download k8s-netperf function
download_netperf() {
  echo "$1"
  curl --fail --retry 8 --retry-all-errors -sS -L "${NETPERF_URL}" | tar -xz
}

# Download and extract k8s-netperf if we haven't already
if [ -f "${NETPERF_FILENAME}" ]; then
  cmd_version=$("./${NETPERF_FILENAME}" --version | awk '/^Version:/{print $2}')
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
cmd=(timeout "${TEST_TIMEOUT}" "./${NETPERF_FILENAME}")

# Function to add flags conditionally
add_flag() {
  local flag_name="$1"
  local flag_value="$2"
  if [ -n "$flag_value" ]; then
    cmd+=("--$flag_name=$flag_value")
  fi
}

print_command() {
  local redacted_cmd=()
  local arg
  for arg in "${cmd[@]}"; do
    case "$arg" in
      --search=*) redacted_cmd+=("--search=<redacted>") ;;
      --prom=*) redacted_cmd+=("--prom=<redacted>") ;;
      --server-prom=*) redacted_cmd+=("--server-prom=<redacted>") ;;
      *) redacted_cmd+=("$arg") ;;
    esac
  done
  printf 'Executing command:'
  printf ' %q' "${redacted_cmd[@]}"
  printf '\n'
}

# ---------------------------------------------------------------------------
# netperf=client / netperf=server node labels (only when client and server run on two nodes of
# one cluster). This run removes a label only when it added it: same node object (UID), same value,
# and this run's field manager as the label's only owner.
# ---------------------------------------------------------------------------

label_manager=""
labeled_nodes=() # "node role uid" for every label this run added

# Templates use bracket keys for the managedFields entries, whose names contain colons.
q="'"
NODE_STATE_TEMPLATE='{.metadata.uid}{"\n"}{.metadata.resourceVersion}{"\n"}{.metadata.labels.netperf}{"\n"}{range .metadata.managedFields[*]}{.manager}{"\t"}{.fieldsV1['"${q}"'f:metadata'"${q}"']['"${q}"'f:labels'"${q}"']['"${q}"'f:netperf'"${q}"']}{"\n"}{end}'

# read_node_state NODE: set node_uid, node_rv, node_value and node_owners (managers owning the label).
read_node_state() {
  local line lines=()
  node_uid="" node_rv="" node_value="" node_owners=()
  if ! kubectl get node "$1" -o "jsonpath=${NODE_STATE_TEMPLATE}" >"${work_dir}/node"; then
    return 1
  fi
  mapfile -t lines <"${work_dir}/node"
  if ((${#lines[@]} < 3)) || [[ -z "${lines[0]}" || -z "${lines[1]}" ]]; then
    return 1
  fi
  node_uid=${lines[0]} node_rv=${lines[1]} node_value=${lines[2]}
  for line in "${lines[@]:3}"; do
    [[ "${line}" == *$'\t'* ]] || return 1
    if [[ -n "${line#*$'\t'}" ]]; then
      node_owners+=("${line%%$'\t'*}")
    fi
  done
}

# is_definite_refusal FILE: the API server or kubectl refused the label write, so nothing was written.
is_definite_refusal() {
  grep -qE '\(Conflict\)|the object has been modified|already has a value' "$1"
}

# check_label_value NODE ROLE VALUE: stop when NODE already has a netperf value other than ROLE.
check_label_value() {
  if [[ -n "$3" && "$3" != "$2" ]]; then
    label_error "node $1 has netperf=$3 but is chosen as the $2 node; remove the label first (kubectl label nodes $1 netperf-)"
  fi
}

# label_node NODE ROLE RV VALUE: add netperf=ROLE to NODE if it is unchanged since it was read.
label_node() {
  local node=$1 role=$2 rv=$3 value=$4 attempt status
  for attempt in 1 2; do
    check_label_value "${node}" "${role}" "${value}"
    if [[ "${value}" == "${role}" ]]; then
      echo "Node ${node} already has netperf=${role}; this run leaves that label as it is"
      return 0
    fi
    status=0
    kubectl label nodes "${node}" "netperf=${role}" \
      "--resource-version=${rv}" "--field-manager=${label_manager}" -o 'jsonpath={.metadata.uid}' \
      >"${work_dir}/label.out" 2>"${work_dir}/label.err" || status=$?
    cat "${work_dir}/label.err"
    if ((status == 0)) && [[ -s "${work_dir}/label.out" ]]; then
      labeled_nodes+=("${node} ${role} $(<"${work_dir}/label.out")")
      echo "Labeled ${node} netperf=${role}"
      return 0
    fi
    if ((status != 0 && attempt == 1)) && is_definite_refusal "${work_dir}/label.err"; then
      echo "Node ${node} changed since it was read; reading it again"
      if ! read_node_state "${node}"; then
        label_error "could not read node ${node} again"
      fi
      rv=${node_rv} value=${node_value}
      continue
    fi
    break
  done
  label_error "labeling ${node} netperf=${role} did not succeed (exit code ${status}); its outcome is unknown, so this run does not treat that label as its own. Check it with 'kubectl get node ${node} --show-labels' and remove it by hand if needed"
}

# unlabel_node NODE ROLE UID: remove netperf=ROLE from NODE if this run still owns it alone.
unlabel_node() {
  local node=$1 role=$2 uid=$3 attempt status reason=""
  for attempt in 1 2; do
    if ! read_node_state "${node}"; then
      reason="the node could not be read"
      break
    fi
    if [[ "${node_uid}" != "${uid}" ]]; then
      reason="the node was replaced (UID ${node_uid}, labeled ${uid})"
      break
    fi
    if [[ "${node_value}" != "${role}" ]]; then
      reason="the label is now netperf=${node_value}"
      break
    fi
    if [[ "${node_owners[*]}" != "${label_manager}" ]]; then
      reason="the label is managed by: ${node_owners[*]:-nobody}"
      break
    fi
    status=0
    kubectl label nodes "${node}" netperf- "--resource-version=${node_rv}" \
      >"${work_dir}/label.out" 2>"${work_dir}/label.err" || status=$?
    cat "${work_dir}/label.out" "${work_dir}/label.err"
    if ((status == 0)); then
      return 0
    fi
    reason="removing it failed (exit code ${status})"
    if ((attempt == 1)) && is_definite_refusal "${work_dir}/label.err"; then
      continue
    fi
    break
  done
  echo "WARNING: left netperf=${role} on node ${node}: ${reason}"
}

remove_own_labels() {
  local entry
  for entry in "${labeled_nodes[@]}"; do
    # shellcheck disable=SC2086 # entry holds "node role uid"
    unlabel_node ${entry}
  done
  labeled_nodes=()
}

label_error() {
  echo "ERROR: $*"
  remove_own_labels
  exit 1
}

label_client_server_nodes() {
  local name rv value client_rv="" client_value="" server_rv="" server_value="" others=()
  echo "Labeling client and server nodes for consistency"
  if ! kubectl get nodes \
    -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!= --no-headers >"${work_dir}/workers"; then
    label_error "could not list the worker nodes"
  fi
  CLIENT_NODE=$(awk 'NR==1{print $1}' "${work_dir}/workers")
  SERVER_NODE=$(awk 'NR==2{print $1}' "${work_dir}/workers")
  if [ -z "$CLIENT_NODE" ] || [ -z "$SERVER_NODE" ]; then
    label_error "Need at least 2 non-infra worker nodes"
  fi
  if ! kubectl get nodes \
    -o 'jsonpath={range .items[*]}{.metadata.name}{"\t"}{.metadata.resourceVersion}{"\t"}{.metadata.labels.netperf}{"\n"}{end}' \
    >"${work_dir}/nodes"; then
    label_error "could not read the node labels"
  fi
  while IFS=$'\t' read -r name rv value; do
    if [[ "${name}" == "${CLIENT_NODE}" ]]; then
      client_rv=${rv} client_value=${value}
    elif [[ "${name}" == "${SERVER_NODE}" ]]; then
      server_rv=${rv} server_value=${value}
    elif [[ -n "${value}" ]]; then
      others+=("${name}=${value}")
    fi
  done <"${work_dir}/nodes"
  if [[ -z "${client_rv}" || -z "${server_rv}" ]]; then
    label_error "the node labels of ${CLIENT_NODE} and ${SERVER_NODE} could not be read"
  fi
  if ((${#others[@]} > 0)); then
    echo "WARNING: other nodes carry a netperf label, which k8s-netperf prefers when placing pods: ${others[*]}"
  fi
  # Both nodes are checked before either label is written.
  check_label_value "${CLIENT_NODE}" client "${client_value}"
  check_label_value "${SERVER_NODE}" server "${server_value}"
  label_manager="e2e-netperf-$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
  label_node "${CLIENT_NODE}" client "${client_rv}" "${client_value}"
  label_node "${SERVER_NODE}" server "${server_rv}" "${server_value}"
}

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

if [ -n "${EXTERNAL_SERVER_ADDRESS}" ]; then
  echo "EXTERNAL_SERVER_ADDRESS is set ${EXTERNAL_SERVER_ADDRESS}"
  add_flag "serverIP" "${EXTERNAL_SERVER_ADDRESS}"
fi

if [[ "${CROSS_CLUSTER}" == "true" ]]; then
  echo "Cross-cluster mode: client pods on the KUBECONFIG cluster, server pods on the SERVER_KUBECONFIG cluster; no node labels"
elif [ "${LOCAL}" = "true" ]; then
  echo "LOCAL mode enabled"
  if [[ "${PLATFORM}" != "microshift" ]]; then
    echo "Removing infra label from worker nodes"
    for node in $(oc get nodes -l node-role.kubernetes.io/infra -o name); do
      oc label "$node" node-role.kubernetes.io/infra- || true
    done
  fi
else
  label_client_server_nodes
fi

# Add flags based on conditions
if [[ "${CROSS_CLUSTER}" == "true" ]]; then
  echo "Cross-cluster mode, not setting --all or --local"
elif [[ "${LOCAL}" != "true" ]]; then
  add_flag "all" "${ALL_SCENARIOS}"
else
  echo "LOCAL=true, not setting --all"
fi
add_flag "clean" "${CLEAN_UP}"
add_flag "config" "${WORKLOAD}"
add_flag "debug" "${DEBUG}"
if [[ "${CROSS_CLUSTER}" != "true" ]]; then
  add_flag "local" "${LOCAL}"
fi
add_flag "metrics" "${METRICS}"
add_flag "prom" "${PROMETHEUS_URL}"
add_flag "search" "${ES_SERVER}"
add_flag "tcp-tolerance" "${TOLERANCE}"
add_flag "uuid" "${UUID}"
add_flag "vm" "${VM}"
add_flag "pod" "${POD}"
add_flag "udnl2" "${UDNL2}"
add_flag "udnl3" "${UDNL3}"
add_flag "bridge" "${BRIDGE}"
add_flag "bridgeNetwork" "${BRIDGE_CONFIG}"
add_flag "localnet" "${LOCALNET}"
add_flag "localnet-config" "${LOCALNET_CONFIG}"
# Add virtctl flag if VM mode is enabled
if [ "${VM}" = true ]; then
  add_flag "use-virtctl" "${USE_VIRTCTL}"
fi
if [[ "${CROSS_CLUSTER}" == "true" ]]; then
  add_flag "server-kubeconfig" "${SERVER_KUBECONFIG}"
  add_flag "server-domain" "${SERVER_DOMAIN}"
  add_flag "server-prom" "${SERVER_PROMETHEUS_URL}"
fi

# Execute the constructed command
print_command
"${cmd[@]}"
run=$?

# With CLEAN_UP=false the caller owns cleanup: after a failed run, make no further cluster call.
case "${CLEAN_UP}" in
  0 | f | F | false | False | FALSE) caller_cleans_up=true ;;
  *) caller_cleans_up=false ;;
esac
if ((run != 0)) && [[ "${caller_cleans_up}" == "true" ]]; then
  log "Finished workload ${0} ${WORKLOAD}, exit code ($run)"
  echo "k8s-netperf failed with CLEAN_UP=${CLEAN_UP}: no label removal, debug queries or indexing; the caller owns cleanup"
  cat ./*.csv
  exit $run
fi

if ((${#labeled_nodes[@]} > 0)); then
  echo "Removing client/server labels added by this run"
  remove_own_labels
fi
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Add debugging info (will be captured in each execution output)
echo "============ Debug Info ============"
echo "k8s-netperf version ${NETPERF_VERSION}"
oc get pods -n netperf -o wide
oc describe pods -n netperf
oc get nodes -o wide
oc get machineset -A || true
if [[ "${CROSS_CLUSTER}" == "true" ]]; then
  echo "============ Server cluster (SERVER_KUBECONFIG) ============"
  oc --kubeconfig "${SERVER_KUBECONFIG}" get pods -n netperf -o wide
  oc --kubeconfig "${SERVER_KUBECONFIG}" describe pods -n netperf
  oc --kubeconfig "${SERVER_KUBECONFIG}" get nodes -o wide
fi

log "Finished workload ${0} ${WORKLOAD}, exit code ($run)"

cat ./*.csv
if [ $run -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="${JOB_START}" JOB_END="${JOB_END}" JOB_STATUS="${JOB_STATUS}" UUID="${UUID}" WORKLOAD="${WORKLOAD_NAME}" ES_SERVER="${ES_SERVER}" PLATFORM="${PLATFORM}" ../../utils/index.sh
exit $run
