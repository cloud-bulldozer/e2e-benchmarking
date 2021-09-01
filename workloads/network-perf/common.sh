#!/usr/bin/env bash

log() {
  echo ${bold}$(date -u):  ${@}${normal}
}

check_cluster_present() {
  echo ""
  oc get clusterversion
  if [ $? -ne 0 ]; then
    log "Workload Failed for cloud $cloud_name, Unable to connect to the cluster"
    exit 1
  fi
  cluster_version=$(oc get clusterversion --no-headers | awk '{ print $2 }')
  echo ""
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
  CRD=${CRD:-ripsaw-uperf-crd.yaml}
  export cr_name=${BENCHMARK:=benchmark}
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
  export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)
  zones=($(oc get nodes -l node-role.kubernetes.io/workload!=,node-role.kubernetes.io/worker -o go-template='{{ range .items }}{{ index .metadata.labels "topology.kubernetes.io/zone" }}{{ "\n" }}{{ end }}' | uniq))
  platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' | tr '[:upper:]' '[:lower:]')
  log "Platform is found to be : ${platform} "

  #Check to see if the infrastructure type is baremetal to adjust script as necessary 
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "BareMetal infastructure: setting isBareMetal accordingly"
    export isBareMetal=true
  else
    export isBareMetal=false
  fi

  #If using baremetal we use different query to find worker nodes
  if [[ "${isBareMetal}" == "true" ]]; then
    log "Colocating uperf pods for baremetal"
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
      log "At least 2 worker nodes are required"
      exit 1
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
    export hostnetwork=false
    export serviceip=true
    if [[ "${isBareMetal}" == "true" ]]; then
      export _metadata_targeted=true
    else  
      export _metadata_targeted=false
    fi
  else
    export hostnetwork=false
    export serviceip=false
  fi

  if [[ -z "$GSHEET_KEY_LOCATION" ]]; then
     export GSHEET_KEY_LOCATION=$HOME/.secrets/gsheet_key.json
  fi

  if [[ ${COMPARE} = "true" ]] && [[ ${COMPARE_WITH_GOLD} == "true" ]]; then
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

  if [ ! -z ${2} ]; then
    export KUBECONFIG=${2}
  fi

  cloud_name=$1
  if [ "$cloud_name" == "" ]; then
    export cloud_name="${network_type}_${platform}_${cluster_version}"
  fi

  if [[ ${COMPARE} == "true" ]]; then
    echo $BASELINE_CLOUD_NAME,$cloud_name > uuid.txt
  else
    echo $cloud_name > uuid.txt
  fi
}

deploy_operator() {
  if [[ "${isBareMetal}" == "false" ]]; then
    log "Removing benchmark-operator namespace, if it already exists"
    oc delete namespace benchmark-operator --ignore-not-found
    log "Cloning benchmark-operator from branch ${operator_branch} of ${operator_repo}"
  else
    log "Baremetal infrastructure: Keeping benchmark-operator namespace"
    log "Cloning benchmark-operator from branch ${operator_branch} of ${operator_repo}"
  fi
    rm -rf benchmark-operator  
    git clone --single-branch --branch ${operator_branch} ${operator_repo} --depth 1
    (cd benchmark-operator && make deploy)
    oc wait --for=condition=available "deployment/benchmark-controller-manager" -n benchmark-operator --timeout=300s
    oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
    oc adm policy -n benchmark-operator add-scc-to-user privileged -z backpack-view
    oc patch scc restricted --type=merge -p '{"allowHostNetwork": true}'
}

deploy_workload() {
  log "Deploying uperf benchmark"
  envsubst < $CRD | oc apply -f -
  log "Sleeping for 60 seconds"
  sleep 60
}

check_logs_for_errors() {
uuid=$(oc describe -n benchmark-operator benchmarks/uperf-${cr_name}-${WORKLOAD}-network-${pairs} | grep  Suuid | awk  '{print $2}')
client_pod=$(oc get pods -n benchmark-operator --no-headers | awk '{print $1}' | grep $uuid | grep uperf-client | awk 'NR==1{print $1}')
if [ ! -z "$client_pod" ]; then
  num_critical=$(oc logs ${client_pod} -n benchmark-operator | grep CRITICAL | wc -l)
  if [ $num_critical -gt 3 ] ; then
    log "Encountered CRITICAL condition more than 3 times in uperf-client logs"
    log "Log dump of uperf-client pod"
    oc logs $client_pod -n benchmark-operator
    delete_benchmark
    exit 1
  fi
fi
}

wait_for_benchmark() {
  uperf_state=1
  for i in {1..480}; do # 2hours
    update
    if [ "${benchmark_state}" == "Error" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
    if [ "${benchmark_state}" == "Failed" ]; then
      log "Benchmark state is Failed, exiting"
      exit 1
    fi
    oc describe -n benchmark-operator benchmarks/uperf-${cr_name}-${WORKLOAD}-network-${pairs} | grep State | grep Complete
    if [ $? -eq 0 ]; then
      log "uperf workload done!"
      uperf_state=$?
      break
    fi
    update
    log "Current status of the uperf ${WORKLOAD} benchmark with ${uline}${benchmark_current_pair} pair/s is ${uline}${benchmark_state}${normal}"
    check_logs_for_errors
    sleep 30
  done

  if [ "$uperf_state" == "1" ] ; then
    log "Workload failed"
    exit 1
  fi
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

init_cleanup() {
  if [[ "${isBareMetal}" == "false" ]]; then
    log "Cloning benchmark-operator from branch ${operator_branch} of ${operator_repo}"
    rm -rf /tmp/benchmark-operator
    git clone --single-branch --branch ${operator_branch} ${operator_repo} /tmp/benchmark-operator --depth 1
    oc delete -f /tmp/benchmark-operator/deploy
    oc delete -f /tmp/benchmark-operator/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
    oc delete -f /tmp/benchmark-operator/resources/operator.yaml  
  else
    log "BareMetal Infrastructure: Skipping cleanup"
  fi
}

delete_benchmark() {
    oc delete benchmarks.ripsaw.cloudbulldozer.io/uperf-${cr_name}-${WORKLOAD}-network-${pairs} -n benchmark-operator
}

update() {
  benchmark_state=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-${cr_name}-${WORKLOAD}-network-${pairs} -n benchmark-operator -o jsonpath='{.status.state}')
  benchmark_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-${cr_name}-${WORKLOAD}-network-${pairs} -n benchmark-operator -o jsonpath='{.status.uuid}')
  benchmark_current_pair=$(oc get benchmarks.ripsaw.cloudbulldozer.io/uperf-${cr_name}-${WORKLOAD}-network-${pairs} -n benchmark-operator -o jsonpath='{.spec.workload.args.pair}')
}

print_uuid() {
  log "Logging uuid.txt"
  cat uuid.txt
}

export TERM=screen-256color
bold=$(tput bold)
uline=$(tput smul)
normal=$(tput sgr0)
python3 -m pip install -r requirements.txt | grep -v 'already satisfied'
check_cluster_present
export_defaults
init_cleanup
check_cluster_health
deploy_operator

