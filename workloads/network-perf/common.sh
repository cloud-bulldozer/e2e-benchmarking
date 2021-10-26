#!/usr/bin/env bash

source env.sh
source ../../utils/benchmark-operator.sh

log() {
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}


check_cluster_health() {
  if [[ ${CERBERUS_URL} ]]; then
    response=$(curl ${CERBERUS_URL})
    if [ "$response" != "True" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
  fi
}


export_defaults() {
  network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
  export client_server_pairs=(1 2 4)
  export cr_name=${BENCHMARK:=benchmark}  
  export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)
  zones=($(oc get nodes -l node-role.kubernetes.io/workload!=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/worker -o go-template='{{ range .items }}{{ index .metadata.labels "topology.kubernetes.io/zone" }}{{ "\n" }}{{ end }}' | uniq))
  platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' | tr '[:upper:]' '[:lower:]')
  log "Platform is found to be: ${platform} "

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

  if [ ${WORKLOAD} == "hostnet" ]
  then
    export HOSTNETWORK=true
    export SERVICEIP=false
  elif [ ${WORKLOAD} == "service" ]
  then
    export HOSTNETWORK=false
    export SERVICEIP=true
    if [[ "${isBareMetal}" == "true" ]]; then
      export METADATA_TARGETED=true
    else  
      export METADATA_TARGETED=false
    fi
  else
    export HOSTNETWORK=false
    export SERVICEIP=false
  fi

  if [[ -z "$GSHEET_KEY_LOCATION" ]]; then
     export GSHEET_KEY_LOCATION=$HOME/.secrets/gsheet_key.json
  fi

  if [[ ${COMPARE} == "true" ]] && [[ ${COMPARE_WITH_GOLD} == "true" ]]; then
    get_gold_ocp_version
    gold_index=$(curl -X GET   "${ES_GOLD}/openshift-gold-${platform}-results/_search" -H 'Content-Type: application/json' -d ' {"query": {"term": {"version": '\"${GOLD_OCP_VERSION}\"'}}}')
    BASELINE_HOSTNET_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."hostnetwork"."num_pairs"."1"."uuid"')
    BASELINE_POD_1P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."podnetwork"."num_pairs"."1"."uuid"')
    BASELINE_POD_2P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."podnetwork"."num_pairs"."2"."uuid"')
    BASELINE_POD_4P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."podnetwork"."num_pairs"."4"."uuid"')
    BASELINE_SVC_1P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."serviceip"."num_pairs"."1"."uuid"')
    BASELINE_SVC_2P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."serviceip"."num_pairs"."2"."uuid"')
    BASELINE_SVC_4P_UUID=$(echo $gold_index | jq -r '."hits".hits[0]."_source"."uperf-benchmark".'\"$gold_sdn\"'."network_type"."serviceip"."num_pairs"."4"."uuid"')
  fi

  _baseline_hostnet_uuid=${BASELINE_HOSTNET_UUID}
  _baseline_pod_1p_uuid=${BASELINE_POD_1P_UUID}
  _baseline_pod_2p_uuid=${BASELINE_POD_2P_UUID}
  _baseline_pod_4p_uuid=${BASELINE_POD_4P_UUID}
  _baseline_svc_1p_uuid=${BASELINE_SVC_1P_UUID}
  _baseline_svc_2p_uuid=${BASELINE_SVC_2P_UUID}
  _baseline_svc_4p_uuid=${BASELINE_SVC_4P_UUID}


  export cloud_name="${network_type}_${platform}_${cluster_version}"

  if [[ ${COMPARE} == "true" ]]; then
    echo $BASELINE_CLOUD_NAME,$cloud_name > uuid.txt
  else
    echo $cloud_name > uuid.txt
  fi
}

deploy_operator() {
  log "Cloning benchmark-operator from branch ${OPERATOR_BRANCH} of ${OPERATOR_REPO}"
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

assign_uuid() {
  compare_uperf_uuid=${benchmark_uuid}
  if [ ${WORKLOAD} == "hostnet" ] ; then
    baseline_uperf_uuid=${_baseline_hostnet_uuid}
  elif [ ${WORKLOAD} == "service" ] ; then
    if [ "${pairs}" == "1" ] ; then
      baseline_uperf_uuid=${_baseline_svc_1p_uuid}
    elif [ "${pairs}" == "2" ] ; then
      baseline_uperf_uuid=${_baseline_svc_2p_uuid}
    elif [ "${pairs}" == "4" ] ; then
      baseline_uperf_uuid=${_baseline_svc_4p_uuid}
    fi
  else
    if [ "${pairs}" == "1" ] ; then
      baseline_uperf_uuid=${_baseline_pod_1p_uuid}
    elif [ "${pairs}" == "2" ] ; then
      baseline_uperf_uuid=${_baseline_pod_2p_uuid}
    elif [ "${pairs}" == "4" ] ; then
      baseline_uperf_uuid=${_baseline_pod_4p_uuid}
    fi
  fi

  if [[ ${COMPARE} == "true" ]]; then
    echo ${baseline_uperf_uuid},${compare_uperf_uuid} >> uuid.txt
  else
    echo ${compare_uperf_uuid} >> uuid.txt
  fi
  
}

run_benchmark_comparison() {
  log "Begining benchamrk comparison"
  ../../utils/touchstone-compare/run_compare.sh uperf ${baseline_uperf_uuid} ${compare_uperf_uuid} ${pairs}
  pairs_array=( "${pairs_array[@]}" "compare_output_${pairs}.yaml" )
  log "Finished benchmark comparison"
}

generate_csv() {
  log "Generating CSV"
  python3 csv_gen.py --files $(echo "${pairs_array[@]}") --latency_tolerance=$latency_tolerance --throughput_tolerance=$throughput_tolerance  
  log "Finished generating CSV"
}

get_gold_ocp_version(){
  current_version=`oc get clusterversion | grep -o [0-9.]* | head -1 | cut -c 1-3`
  export GOLD_OCP_VERSION=$( bc <<< "$current_version - 0.1" )
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

export TERM=screen-256color
python3 -m pip install -r requirements.txt | grep -v 'already satisfied'
export_defaults
check_cluster_health
deploy_operator

