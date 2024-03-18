#!/bin/bash -e

set -e

ES_SERVER=${ES_SERVER=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
LOG_LEVEL=${LOG_LEVEL:-info}
if [ "$KUBE_BURNER_VERSION" = "default" ]; then
    unset KUBE_BURNER_VERSION
fi
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.1.0}
CHURN=${CHURN:-false}
WORKLOAD='node-density'
QPS=${QPS:-20}
BURST=${BURST:-20}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
UUID=${UUID:-$(uuidgen)}
KUBE_DIR=${KUBE_DIR:-/tmp}
export ITERATIONS=${ITERATIONS:-341}
WHEREABOUTS_OVERLAPS=0

download_binary(){
  KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-linux-x86_64.tar.gz"
  curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
}
function cleanup_whereabouts(){
    
    # remove IP pool
    oc delete ippools.whereabouts.cni.cncf.io '10.1.0.0-21' -n openshift-multus

    readarray -t overlaps < <( oc get overlappingrangeipreservations.whereabouts.cni.cncf.io -n openshift-multus --no-headers=true | awk '{print $1}' );
    WHEREABOUTS_OVERLAPS=${#overlaps[@]}

    # also need to remove the overlapping reservations
    for i in "${overlaps[@]}"; do
        oc delete overlappingrangeipreservations.whereabouts.cni.cncf.io $i -n openshift-multus;
    done

    # This will remove the whereabouts plugin from the network operator. The operator will stop the whereabouts pods on its own
    oc patch network.operator.openshift.io cluster --type=json -p='[{"op":"remove","path":"/spec/additionalNetworks"}]'


}
function install_whereabouts(){

    # Install whereabouts reconciler daemon
    oc patch network.operator.openshift.io cluster --patch-file=reconciler.yml --type=merge
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "whereabouts reconciler daemon installed via oc patch"
    else
        echo "failure - reconciler daemon not installed"
        exit $exit_code
    fi
    # give the pods time to come up.
    sleep_time=10
    echo "sleeping for $sleep_time seconds to allow reconciler pods to start"
    sleep $sleep_time
}



download_binary
if [[ ${WORKLOAD} =~ "index" ]]; then
  cmd="${KUBE_DIR}/kube-burner-ocp index --uuid=${UUID} --start=$START_TIME --end=$((END_TIME+600)) --log-level ${LOG_LEVEL}"
else
  cmd="${KUBE_DIR}/kube-burner-ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC} --uuid ${UUID}"
  cmd+=" ${EXTRA_FLAGS}"
fi
if [[ ${WORKLOAD} =~ "cluster-density" ]]; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi
if [[ -n ${MC_KUBECONFIG} ]] && [[ -n ${ES_SERVER} ]]; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
  hypershift
fi
# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=ripsaw-kube-burner"
fi

install_whereabouts

# Capture the exit code of the run, but don't exit the script if it fails.
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

echo $WHEREABOUTS_OVERLAPS
cleanup_whereabouts

exit $exit_code || $WHEREABOUTS_OVERLAPS
