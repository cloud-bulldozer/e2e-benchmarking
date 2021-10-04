#!/usr/bin/env bash

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
  operator_repo=${OPERATOR_REPO:=https://github.com/cloud-bulldozer/benchmark-operator.git}
  operator_branch=${OPERATOR_BRANCH:=master}
  export _es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
  _es_baseline=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
  export _metadata_collection=${METADATA_COLLECTION:=true}
  export _metadata_targeted=true
  export COMPARE=${COMPARE:=false}
  network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
  gold_sdn=${GOLD_SDN:=openshiftsdn}
  throughput_tolerance=${THROUGHPUT_TOLERANCE:=10}
  latency_tolerance=${LATENCY_TOLERANCE:=10}
  export client_server_pairs=(1 2 4)
  export pin=true
  export networkpolicy=${NETWORK_POLICY:=false}
  export multi_az=${MULTI_AZ:=true}
  zones=($(oc get nodes -l node-role.kubernetes.io/workload!=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/worker -o go-template='{{ range .items }}{{ index .metadata.labels "topology.kubernetes.io/zone" }}{{ "\n" }}{{ end }}' | uniq))
  platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' | tr '[:upper:]' '[:lower:]')
  log "Platform is found to be: ${platform} "
  # If multi_az we use one node from the two first AZs
  if [[ ${platform} == "vsphere" ]]; then
    nodes=($(oc get nodes -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="" -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}'))
    if [[ ${#nodes[@]} -lt 2 ]]; then
      log "At least 2 worker nodes placed are required"
      exit 1
    fi
    export server=${nodes[0]}
    export client=${nodes[1]}
  elif [[ ${multi_az} == "true" ]]; then
    # Get AZs from worker nodes
    log "Colocating uperf pods in different AZs"
    if [[ ${#zones[@]} -gt 1 ]]; then
      export server=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",topology.kubernetes.io/zone=${zones[0]} -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | head -n1)
      export client=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",topology.kubernetes.io/zone=${zones[1]} -o jsonpath='{range .items[*]}{ .metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | tail -n1)
    else
      log "At least 2 worker nodes placed in different topology zones are required"
      exit 1
    fi
  # If multi_az is disabled we use the two first nodes from the first AZ
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
    export hostnetwork=true
    export serviceip=false
  elif [ ${WORKLOAD} == "service" ]
  then
    export _metadata_targeted=false
    export hostnetwork=false
    export serviceip=true
  else
    export hostnetwork=false
    export serviceip=false
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
  deploy_benchmark_operator ${operator_repo} ${operator_branch}
  rm -rf benchmark-operator
  git clone --single-branch --branch ${operator_branch} ${operator_repo} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
  oc adm policy -n benchmark-operator add-scc-to-user privileged -z backpack-view
  oc patch scc restricted --type=merge -p '{"allowHostNetwork": true}'
}

run_workload() {
  local TMPCR=$(mktemp)
  log "Deploying uperf benchmark"
  envsubst < $1 > ${TMPCR}
  run_benchmark ${TMPCR} 7200
}

assign_uuid() {
  update
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
  ../../utils/touchstone-compare/run_compare.sh uperf ${baseline_uperf_uuid} ${compare_uperf_uuid} ${pairs}
  pairs_array=( "${pairs_array[@]}" "compare_output_${pairs}.yaml" )
}

generate_csv() {
  python3 csv_gen.py --files $(echo "${pairs_array[@]}") --latency_tolerance=$latency_tolerance --throughput_tolerance=$throughput_tolerance  
}

delete_benchmark() {
  oc delete benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-${WORKLOAD}-network-${pairs} -n benchmark-operator
}


update() {
  benchmark_state=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-${WORKLOAD}-network-${pairs} -n benchmark-operator -o jsonpath='{.status.state}')
  benchmark_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-${WORKLOAD}-network-${pairs} -n benchmark-operator -o jsonpath='{.status.uuid}')
  benchmark_current_pair=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-benchmark-${WORKLOAD}-network-${pairs} -n benchmark-operator -o jsonpath='{.spec.workload.args.pair}')
}

get_gold_ocp_version(){
  current_version=`oc get clusterversion | grep -o [0-9.]* | head -1 | cut -c 1-3`
  export GOLD_OCP_VERSION=$( bc <<< "$current_version - 0.1" )
}

export TERM=screen-256color
bold=$(tput bold)
uline=$(tput smul)
normal=$(tput sgr0)
python3 -m pip install -r requirements.txt | grep -v 'already satisfied'
export_defaults
check_cluster_health
deploy_operator
