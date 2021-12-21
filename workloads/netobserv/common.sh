#!/usr/bin/env bash

source env.sh
source ../../utils/common.sh
source ../../utils/benchmark-operator.sh
source ../../utils/compare.sh

check_cluster_health() {
  if [[ ${CERBERUS_URL} ]]; then
    response=$(curl ${CERBERUS_URL})
    if [ "$response" != "True" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
  fi
}


get_gold_ocp_version(){
  current_version=$(oc get clusterversion | grep -o [0-9.]* | head -1 | cut -c 1-3)
  GOLD_OCP_VERSION=$( bc <<< "$current_version - 0.1" )
}


export_defaults() {
  network_type=$(oc get network cluster -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
  export UUID=$(uuidgen)
  export client_server_pairs=(1 2 4)
  export CR_NAME=${BENCHMARK:=benchmark}
  export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)
  zones=($(oc get nodes -l node-role.kubernetes.io/workload!=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/worker -o go-template='{{ range .items }}{{ index .metadata.labels "topology.kubernetes.io/zone" }}{{ "\n" }}{{ end }}' | uniq))
  platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' | tr '[:upper:]' '[:lower:]')
  log "Platform is found to be: ${platform} "
  if [[ ${COMPARE_WITH_GOLD} == "true" ]]; then
    ES_SERVER_BASELINE=${ES_GOLD}
    log "Comparison with gold enabled, getting golden results from ES: ${ES_SERVER_BASELINE}"
    get_gold_ocp_version
    local gold_index=$(curl "${ES_GOLD}/openshift-gold-${platform}-results/_search" -H 'Content-Type: application/json' -d ' {"query": {"term": {"version": '\"${GOLD_OCP_VERSION}\"'}}}')
    BASELINE_HOSTNET_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."hostnetwork"."num_pairs"."1"."uuid"')
    BASELINE_POD_UUID[1]=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."podnetwork"."num_pairs"."1"."uuid"')
    BASELINE_POD_UUID[2]=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."podnetwork"."num_pairs"."2"."uuid"')
    BASELINE_POD_UUID[4]=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."podnetwork"."num_pairs"."4"."uuid"')
    BASELINE_SVC_UUID[1]=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."serviceip"."num_pairs"."1"."uuid"')
    BASELINE_SVC_UUID[2]=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."serviceip"."num_pairs"."2"."uuid"')
    BASELINE_SVC_UUID[4]=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"${GOLD_SDN}\"'."network_type"."serviceip"."num_pairs"."4"."uuid"')
  fi
  #Check to see if the infrastructure type is baremetal to adjust script as necessary 
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "BareMetal infastructure: setting isBareMetal accordingly"
    export isBareMetal=true
  else
    export isBareMetal=false
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
  rm -rf benchmark-operator
  git clone --single-branch --branch ${OPERATOR_BRANCH} ${OPERATOR_REPO} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z backpack-view
  oc patch scc restricted --type=merge -p '{"allowHostNetwork": true}'
}

run_workload() {
  log "Deploying benchmark"
  local TMPCR=$(mktemp)
  envsubst < $1 > ${TMPCR}
  run_benchmark ${TMPCR} ${TEST_TIMEOUT}
  local rc=$?
  if [[ ${TEST_CLEANUP} == "true" ]]; then
    log "Cleaning up benchmark"
    kubectl delete -f ${TMPCR}
  fi
  return ${rc}
}


run_benchmark_comparison() {
  if [[ -n ${ES_SERVER} ]]; then
    log "Installing touchstone"
    install_touchstone
    if [[ -n ${ES_SERVER_BASELINE} ]] && [[ -n ${BASELINE_UUID} ]]; then
      log "Comparing with baseline"
      compare "${ES_SERVER_BASELINE} ${ES_SERVER}" "${BASELINE_UUID} ${UUID}" ${COMPARISON_CONFIG} csv
    else
      log "Querying results"
      compare ${ES_SERVER} ${UUID} ${COMPARISON_CONFIG} csv
    fi
    if [[ -n ${GSHEET_KEY_LOCATION} ]] && [[ -n ${COMPARISON_OUTPUT} ]]; then
      gen_spreadsheet network-performance ${COMPARISON_OUTPUT} ${EMAIL_ID_FOR_RESULTS_SHEET} ${GSHEET_KEY_LOCATION}
    fi
    log "Removing touchstone"
    remove_touchstone
  fi
}


snappy_backup(){
  log "Snappy server as backup enabled"
  source ../../utils/snappy-move-results/common.sh
  csv_list=`find . -name "*.csv"` 
  mkdir -p files_list
  cp $csv_list ./files_list
  tar -zcf snappy_files.tar.gz ./files_list
  local snappy_path="${SNAPPY_USER_FOLDER}/${runid}${platform}-${cluster_version}-${network_type}/${1}/${folder_date_time}/"
  generate_metadata > metadata.json  
  ../../utils/snappy-move-results/run_snappy.sh snappy_files.tar.gz $snappy_path
  ../../utils/snappy-move-results/run_snappy.sh metadata.json $snappy_path
  store_on_elastic
  rm -rf files_list
}

patch_cno() {
  if [[ ! -z $1 ]]; then
    log "patching CNO with goflow-kube IP as collector"
    oc patch networks.operator.openshift.io cluster --type='json' -p "$(sed -e "s/GF_IP/$1/" ${NETOBSERV_DIR}/config/samples/net-cluster-patch.json)"
  else
    log "updating CNO by removing goflow-kube IP as collector"

    sed -i 's/add/remove/g' ${NETOBSERV_DIR}/config/samples/net-cluster-patch.json
    oc patch networks.operator.openshift.io cluster --type='json' -p "$(sed -e "s/GF_IP/$GF_IP/" ${NETOBSERV_DIR}/config/samples/net-cluster-patch.json)"
  fi
}

deploy_netobserv_operator() {
  log "deploying network-observability operator and flowcollector CR"
  git clone https://github.com/netobserv/network-observability-operator.git
  export NETOBSERV_DIR=${PWD}/network-observability-operator
  add_go_path
  log `go version`
  log $PATH
  cd ${NETOBSERV_DIR} && make deploy && cd -
  log "deploying flowcollector as service"
  oc apply -f ${NETOBSERV_DIR}/config/samples/flows_v1alpha1_flowcollector.yaml
  sleep 15
  export GF_IP=$(oc get svc goflow-kube -n network-observability -ojsonpath='{.spec.clusterIP}')
  log "goflow collector IP: ${GF_IP}"
  patch_cno ${GF_IP}
}

delete_flowcollector() {
  log "deleteing flowcollector"
  cd $NETOBSERV_DIR && oc delete -f $NETOBSERV_DIR/config/samples/flows_v1alpha1_flowcollector.yaml
  patch_cno ''
  rm -rf $NETOBSERV_DIR
}

add_go_path() {
  log "adding go bin to PATH"
  export PATH=$PATH:/usr/local/go/bin
}


export_defaults
check_cluster_health
deploy_operator
