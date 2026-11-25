#!/usr/bin/env bash
set -e

source ./env.sh
source ../../utils/common.sh

set +e

CROSS_CLUSTER=false
if [[ -n "${SERVER_KUBECONFIG}" ]]; then
  CROSS_CLUSTER=true
fi

# Grace before SIGKILL for every bounded command except k8s-netperf (TEST_KILL_AFTER).
GRACE=10

# ---------------------------------------------------------------------------
# Input checks: they run before the download and before any cluster call.
# ---------------------------------------------------------------------------

input_error() {
  echo "ERROR: $*"
  exit 1
}

# parse_number TEXT: set $parsed to TEXT read as a floating-point number (current locale, then C).
parse_number() {
  printf -v parsed '%.17g' "$1" 2>/dev/null || LC_ALL=C printf -v parsed '%.17g' "$1" 2>/dev/null
}

# is_duration VALUE: true when VALUE is a finite duration greater than zero that GNU timeout accepts:
# a number as strtod reads it, then at most one of s, m, h, d.
is_duration() {
  local value=$1 parsed
  [[ -n "$value" && "$value" != *[\'\"]* ]] || return 1
  if parse_number "$value"; then
    :
  elif [[ "$value" == *[smhd] ]] && parse_number "${value%?}"; then
    :
  else
    return 1
  fi
  case "$parsed" in
    0 | -* | inf | nan) return 1 ;;
  esac
  timeout "$value" true 2>/dev/null
  [[ $? -ne 125 ]]
}

if ! timeout --foreground -k 1 10 true 2>/dev/null; then
  input_error "GNU timeout (coreutils) with --foreground and -k is required"
fi

for deadline in TEST_TIMEOUT TEST_KILL_AFTER DOWNLOAD_TIMEOUT CALL_TIMEOUT INDEX_TIMEOUT; do
  if ! is_duration "${!deadline}"; then
    input_error "${deadline}=${!deadline} is not a duration greater than zero (seconds, or a number with s, m, h or d)"
  fi
done

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

# ---------------------------------------------------------------------------
# Bounded commands. Every external command runs through bounded(): its own process group in this
# session, a GNU timeout deadline, and a stop signal to run.sh forwarded to it exactly once.
# ---------------------------------------------------------------------------

work_dir=$(mktemp -d) || input_error "cannot create a temporary directory"
trap 'rm -rf "${work_dir}"' EXIT

received=0     # stop signals received (INT, TERM, HUP)
stop_signal="" # the first one, for the exit status
active=""      # monitor (timeout) of the running bounded command, once registered

# shellcheck disable=SC2329 # called by the traps below
on_signal() {
  received=$((received + 1))
  if [[ -z "${stop_signal}" ]]; then
    stop_signal=$1
  fi
  if [[ -n "${active}" ]]; then
    kill -TERM "${active}" 2>/dev/null || true
  fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal HUP' HUP

exit_on_signal() {
  local code=143
  case "${stop_signal}" in
    INT) code=130 ;;
    HUP) code=129 ;;
  esac
  log "Stopped by SIG${stop_signal}: no further cluster call, exit code (${code})"
  exit "${code}"
}

# Test points: does nothing. test-run.py replaces this function in its own copy of run.sh to signal
# run.sh at the three points of bounded() where the order of a signal and the registration matters.
test_hook() {
  :
}

# bounded LIMIT KILL_AFTER CMD...: run CMD, ending it LIMIT after its start (TERM, then KILL after
# KILL_AFTER), and return its status. GNU timeout --foreground sends each signal once and to CMD only;
# job control at the launch gives the monitor and CMD their own process group, so signals to run.sh's
# process group reach them only through on_signal. When the monitor has ended, whatever is left in
# that group is killed.
bounded() {
  local limit=$1 kill_after=$2 pid pre before status
  shift 2
  if ((received > 0)); then
    exit_on_signal
  fi
  set -m
  timeout --foreground -k "${kill_after}" "${limit}" "$@" </dev/null &
  pid=$!
  set +m
  test_hook launched "$@"
  # One command, so no trap runs between these assignments: a signal before them is counted in pre
  # and forwarded below, a signal after them is forwarded by its trap.
  pre=${received} active=${pid}
  while ((pre > 0)); do
    kill -TERM "${pid}" 2>/dev/null || true
    pre=$((pre - 1))
  done
  test_hook registered "$@"
  while true; do
    before=${received}
    status=0
    wait "${pid}" 2>/dev/null || status=$?
    if ((received == before)); then
      break
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      break
    fi
    test_hook rewait "$@"
  done
  active=""
  kill -KILL -- "-${pid}" 2>/dev/null || true
  if ((received > 0)); then
    exit_on_signal
  fi
  return "${status}"
}

# ---------------------------------------------------------------------------
# k8s-netperf binary
# ---------------------------------------------------------------------------

download_netperf() {
  local status=0
  echo "$1"
  # shellcheck disable=SC2016 # $1 is expanded by the inner bash
  bounded "${DOWNLOAD_TIMEOUT}" "${GRACE}" bash -c \
    'set -o pipefail; curl --fail --retry 8 --retry-all-errors -sS -L "$1" | tar -xz' download "${NETPERF_URL}" ||
    status=$?
  if ((status != 0)); then
    echo "ERROR: downloading k8s-netperf failed or exceeded DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT} (exit code ${status})"
    exit "${status}"
  fi
}

# Download and extract k8s-netperf if we haven't already
if [ -f "${NETPERF_FILENAME}" ]; then
  cmd_version=""
  if bounded "${CALL_TIMEOUT}" "${GRACE}" "./${NETPERF_FILENAME}" --version >"${work_dir}/version"; then
    cmd_version=$(awk '/^Version:/{print $2}' "${work_dir}/version")
  fi
  if [[ -n "${cmd_version}" && "${NETPERF_VERSION}" == *"${cmd_version}"* ]]; then
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

JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize the command var
cmd=("./${NETPERF_FILENAME}")

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
  printf ' %q' timeout --foreground -k "${TEST_KILL_AFTER}" "${TEST_TIMEOUT}" "${redacted_cmd[@]}"
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
  if ! bounded "${CALL_TIMEOUT}" "${GRACE}" kubectl get node "$1" -o "jsonpath=${NODE_STATE_TEMPLATE}" >"${work_dir}/node"; then
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
    bounded "${CALL_TIMEOUT}" "${GRACE}" kubectl label nodes "${node}" "netperf=${role}" \
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
    bounded "${CALL_TIMEOUT}" "${GRACE}" kubectl label nodes "${node}" netperf- "--resource-version=${node_rv}" \
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
  if ! bounded "${CALL_TIMEOUT}" "${GRACE}" kubectl get nodes \
    -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!= --no-headers >"${work_dir}/workers"; then
    label_error "could not list the worker nodes"
  fi
  CLIENT_NODE=$(awk 'NR==1{print $1}' "${work_dir}/workers")
  SERVER_NODE=$(awk 'NR==2{print $1}' "${work_dir}/workers")
  if [ -z "$CLIENT_NODE" ] || [ -z "$SERVER_NODE" ]; then
    label_error "Need at least 2 non-infra worker nodes"
  fi
  if ! bounded "${CALL_TIMEOUT}" "${GRACE}" kubectl get nodes \
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
    bounded "${CALL_TIMEOUT}" "${GRACE}" oc label nodes -l node-role.kubernetes.io/infra node-role.kubernetes.io/infra- || true
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
run=0
bounded "${TEST_TIMEOUT}" "${TEST_KILL_AFTER}" "${cmd[@]}" || run=$?

# With CLEAN_UP=false the caller owns cleanup: after a failed run, make no further cluster call.
case "${CLEAN_UP}" in
  0 | f | F | false | False | FALSE) caller_cleans_up=true ;;
  *) caller_cleans_up=false ;;
esac
if ((run != 0)) && [[ "${caller_cleans_up}" == "true" ]]; then
  log "Finished workload ${0} ${WORKLOAD}, exit code ($run)"
  echo "k8s-netperf failed with CLEAN_UP=${CLEAN_UP}: no label removal, debug queries or indexing; the caller owns cleanup"
  cat ./*.csv
  if ((received > 0)); then
    exit_on_signal
  fi
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
bounded "${CALL_TIMEOUT}" "${GRACE}" oc get pods -n netperf -o wide
bounded "${CALL_TIMEOUT}" "${GRACE}" oc describe pods -n netperf
bounded "${CALL_TIMEOUT}" "${GRACE}" oc get nodes -o wide
bounded "${CALL_TIMEOUT}" "${GRACE}" oc get machineset -A || true
if [[ "${CROSS_CLUSTER}" == "true" ]]; then
  echo "============ Server cluster (SERVER_KUBECONFIG) ============"
  bounded "${CALL_TIMEOUT}" "${GRACE}" oc --kubeconfig "${SERVER_KUBECONFIG}" get pods -n netperf -o wide
  bounded "${CALL_TIMEOUT}" "${GRACE}" oc --kubeconfig "${SERVER_KUBECONFIG}" describe pods -n netperf
  bounded "${CALL_TIMEOUT}" "${GRACE}" oc --kubeconfig "${SERVER_KUBECONFIG}" get nodes -o wide
fi

log "Finished workload ${0} ${WORKLOAD}, exit code ($run)"

cat ./*.csv
if [ $run -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi

# utils/index.sh is shared with other workloads. Its oc and kubectl calls get CALL_TIMEOUT each through
# shims first on its PATH; their output goes through files, so a leftover child of a call cannot keep
# index.sh waiting. Everything index.sh starts stays in its process group, which bounded() ends.
# The shims spool output under work_dir, which the EXIT trap removes even when a shim is killed.
shim_dir="${work_dir}/bin"
spool_dir="${work_dir}/spool"
mkdir -p "${shim_dir}" "${spool_dir}"
{
  echo '#!/usr/bin/env bash'
  printf 'spool_dir=%q\n' "${spool_dir}"
  cat <<'EOF'
self_dir=$(cd "$(dirname "$0")" && pwd)
name=$(basename "$0")
real=""
IFS=: read -ra dirs <<<"${PATH}"
for dir in "${dirs[@]}"; do
  if [[ -n "${dir}" && "${dir}" != "${self_dir}" && -f "${dir}/${name}" && -x "${dir}/${name}" ]]; then
    real="${dir}/${name}"
    break
  fi
done
if [[ -z "${real}" ]]; then
  echo "${name}: command not found" >&2
  exit 127
fi
out=$(mktemp "${spool_dir}/out.XXXXXX") && err=$(mktemp "${spool_dir}/err.XXXXXX") || exit 1
status=0
timeout --foreground -k 10 "${CALL_TIMEOUT}" "${real}" "$@" </dev/null >"${out}" 2>"${err}" || status=$?
cat "${out}"
cat "${err}" >&2
rm -f "${out}" "${err}"
exit "${status}"
EOF
} >"${shim_dir}/oc"
cp "${shim_dir}/oc" "${shim_dir}/kubectl"
chmod +x "${shim_dir}/oc" "${shim_dir}/kubectl"
bounded "${INDEX_TIMEOUT}" "${GRACE}" env PATH="${shim_dir}:${PATH}" JOB_START="${JOB_START}" JOB_END="${JOB_END}" \
  JOB_STATUS="${JOB_STATUS}" UUID="${UUID}" WORKLOAD="${WORKLOAD_NAME}" ES_SERVER="${ES_SERVER}" PLATFORM="${PLATFORM}" \
  ../../utils/index.sh
if ((received > 0)); then
  exit_on_signal
fi
exit $run
