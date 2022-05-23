#!/usr/bin/env bash

source env.sh
source ../../utils/common.sh
source ../../utils/benchmark-operator.sh

openshift_login

export_defaults() {
  network_type=$(oc get network cluster -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
  export UUID=$(uuidgen)
  export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath="{.status.infrastructureName}")
  export PROM_TOKEN=$(oc sa get-token -n openshift-monitoring prometheus-k8s || oc sa new-token -n openshift-monitoring prometheus-k8s || oc create token -n openshift-monitoring prometheus-k8s --duration=6h)
  nodes=($(oc get nodes -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="" -o custom-columns=name:{.metadata.name} --no-headers))
  if [[ ${#nodes[@]} -lt 2 ]]; then
    log "At least 2 worker nodes are required"
    exit 1
  fi
}

deploy_operator() {
  deploy_benchmark_operator
}

export_defaults
deploy_operator
