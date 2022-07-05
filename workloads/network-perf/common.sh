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
  local baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)
  zones=($(oc get nodes -l node-role.kubernetes.io/workload!=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/worker -o go-template='{{ range .items }}{{ index .metadata.labels "topology.kubernetes.io/zone" }}{{ "\n" }}{{ end }}' | uniq))
  platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' | tr '[:upper:]' '[:lower:]')
  #Check to see if the infrastructure type is baremetal to adjust script as necessary 
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "BareMetal infastructure: setting isBareMetal accordingly"
    isBareMetal=true
  else
    isBareMetal=false
  fi

  #If using baremetal we use different query to find worker nodes
  if [[ "${isBareMetal}" == "true" ]]; then
    #Installing python3.8
    sudo yum -y install python3.8

    nodeCount=$(oc get nodes --no-headers -l node-role.kubernetes.io/worker | wc -l)
    if [[ ${nodeCount} -ge 2 ]]; then
      serverNumber=$(( $RANDOM %${nodeCount} + 1 ))
      clientNumber=$(( $RANDOM %${nodeCount} + 1 ))
      while (( $serverNumber == $clientNumber ))
        do
          clientNumber=$(( $RANDOM %${nodeCount} + 1 ))
        done
      export server=$(oc get nodes --no-headers -l node-role.kubernetes.io/worker | awk 'NR=='${serverNumber}'{print $1}')
      export client=$(oc get nodes --no-headers -l node-role.kubernetes.io/worker | awk 'NR=='${clientNumber}'{print $1}')
    else
      log "Colocating uperf pods for baremetal, since only one worker node available"
      export server=$(oc get nodes --no-headers -l node-role.kubernetes.io/worker | awk 'NR=='1'{print $1}')
      export client=$(oc get nodes --no-headers -l node-role.kubernetes.io/worker | awk 'NR=='1'{print $1}')
    fi  
    log "Finished assigning server and client nodes"
    log "Server to be scheduled on node: $server"
    log "Client to be scheduled on node: $client"
    # If multi_az we use one node from the two first AZs
  elif [[ ${platform} == "vsphere" ]]; then
    nodes=($(oc get nodes -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="" -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}'))
    if [[ ${#nodes[@]} -lt 2 ]]; then
      log "At least 2 worker nodes placed are required"
      exit 1
    fi
    export server=${nodes[0]}
    export client=${nodes[1]}
  elif [[ ${MULTI_AZ} == "true" ]]; then
    # Get AZs from worker nodes
    log "Colocating uperf pods in different AZs"
    if [[ ${#zones[@]} -gt 1 ]]; then
      export server=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",topology.kubernetes.io/zone=${zones[0]} -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | head -n1)
      export client=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",topology.kubernetes.io/zone=${zones[1]} -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | tail -n1)
    else
      log "At least 2 worker nodes placed in different topology zones are required"
      exit 1
    fi
  # If MULTI_AZ is disabled we use the two first nodes from the first AZ
  else
    nodes=($(oc get nodes -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",topology.kubernetes.io/zone=${zones[0]} -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}'))
    if [[ ${#nodes[@]} -lt 2 ]]; then
      log "At least 2 worker nodes placed in the topology zone ${zones[0]} are required"
      exit 1
    fi
    log "Colocating uperf pods in the same AZ"
    export server=${nodes[0]}
    export client=${nodes[1]}
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
