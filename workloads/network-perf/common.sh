#!/usr/bin/env bash

source env.sh
source ../../utils/common.sh
source ../../utils/benchmark-operator.sh
source ../../utils/compare.sh

openshift_login

export_defaults() {
  network_type=$(oc get network cluster -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
  export UUID=$(uuidgen)
  export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath="{.status.infrastructureName}")
  export PROM_TOKEN=$(oc sa get-token -n openshift-monitoring prometheus-k8s || oc sa new-token -n openshift-monitoring prometheus-k8s || oc create token -n openshift-monitoring  prometheus-k8s)
  nodes=($(oc get nodes -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="" -o custom-columns=name:{.metadata.name} --no-headers))
  if [[ ${#nodes[@]} -lt 2 ]]; then
    log "At least 2 worker nodes are required"
    exit 1
  fi
}

deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
}

run_benchmark_comparison() {
  if [[ -n ${ES_SERVER} ]]; then
    log "Installing touchstone"
    install_touchstone
    if [[ -n ${ES_SERVER_BASELINE} ]] && [[ -n ${BASELINE_UUID} ]]; then
      log "Comparing with baseline"
      compare "${ES_SERVER_BASELINE} ${ES_SERVER}" "${BASELINE_UUID} ${UUID}" ${COMPARISON_CONFIG} ${GEN_CSV}
    else
      log "Querying results"
      compare ${ES_SERVER} ${UUID} ${COMPARISON_CONFIG} ${GEN_CSV}
    fi
    if [[ -n ${GSHEET_KEY_LOCATION} ]] && [[ ${GEN_CSV} == "true" ]]; then
      gen_spreadsheet network-performance ${COMPARISON_OUTPUT} ${EMAIL_ID_FOR_RESULTS_SHEET} ${GSHEET_KEY_LOCATION}
    fi
    log "Removing touchstone"
    remove_touchstone
  fi
}

export_defaults
deploy_operator
