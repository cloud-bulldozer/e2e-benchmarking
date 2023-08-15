#!/usr/bin/env bash
set -e

source ./env.sh
source ../../utils/common.sh

curl -sS -L $NETPERF_URL | tar -xz

# Assuming kubeconfig is set
if [[ "$(oc get ns netperf --no-headers --ignore-not-found)" == ""  ]]; then
  oc create ns netperf
  oc create sa netperf -n netperf
fi

oc adm policy add-scc-to-user hostnetwork -z netperf -n netperf

log "###############################################"
log "Workload: ${WORKLOAD}"
log "UUID: ${UUID}"
log "###############################################"

# Capture exit code of k8s-netperf
set +e

JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
timeout $TEST_TIMEOUT ./k8s-netperf --debug --metrics --all --config ${WORKLOAD} --search $ES_SERVER --tcp-tolerance ${TOLERANCE} --clean=true --uuid $UUID
run=$?
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Add debugging info (will be captured in each execution output)
echo "============ Debug Info ============"
echo k8s-netperf version $NETPERF_VERSION
oc get pods -n netperf -o wide
oc get nodes -o wide
oc get machineset -A

log "Finished workload ${0} ${WORKLOAD}, exit code ($run)"

cat *.csv
if [ $run -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" ES_SERVER="$ES_SERVER" ../../utils/index.sh
exit $run
