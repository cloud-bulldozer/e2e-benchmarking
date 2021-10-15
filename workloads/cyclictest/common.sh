source env.sh

# If ES_SERVER is set and empty we disable ES indexing and metadata collection
if [[ -v ES_SERVER ]] && [[ -z ${ES_SERVER} ]]; then
  export METADATA_COLLECTION=false
else
  export PROM_TOKEN=$(oc -n openshift-monitoring sa get-token prometheus-k8s)
fi
export NODE_SELECTOR_KEY="node-role.kubernetes.io/worker"
export NODE_SELECTOR_VALUE=""
export WAIT_WHEN_FINISHED=true
export WAIT_FOR=[]
export TOLERATIONS="[{key: role, value: workload, effect: NoSchedule}]"
export UUID=$(uuidgen)

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
  CRD=${CRD:-ripsaw-cyclictest-crd.yaml}
  export _es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
  _es_baseline=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
  export _metadata_collection=${METADATA_COLLECTION:=true}
  export _metadata_targeted=true
  export COMPARE=${COMPARE:=false}
  network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
  gold_sdn=${GOLD_SDN:=openshiftsdn}
  throughput_tolerance=${THROUGHPUT_TOLERANCE:=5}
  latency_tolerance=${LATENCY_TOLERANCE:=5}
  export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)

  if [[ -z "$GSHEET_KEY_LOCATION" ]]; then
     export GSHEET_KEY_LOCATION=$HOME/.secrets/gsheet_key.json
  fi

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


deploy_perf_profile() {
  if [[ $(oc get performanceprofile --no-headers | awk '{print $1}') == "benchmark-performance-profile-0" ]]; then
    log "Performance profile already exists. Applying the cyclictest profile"
    oc apply -f perf_profile.yaml
    if [ $? -ne 0 ]; then
      log "Couldn't apply performance profile, exiting!"
      exit 1
    fi
  else 
    if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
      log "Trying to find a suitable node for testpmd"
      # iterate over worker nodes until we have at least 1 
      worker_count=0
      testpmd_workers=()
      workers=$(oc get bmh -n openshift-machine-api | grep worker | awk '{print $1}')
      until [ $worker_count -eq 1 ]; do
        for worker in $workers; do
    	  worker_ip=$(oc get node $worker -o json | jq -r ".status.addresses[0].addres" | grep 192 )
          if [[ ! -z "$worker_ip" ]]; then 
            testpmd_workers+=( $worker )
  	    ((worker_count=worker_count+1))
          fi
        done
      done
    fi
    # label the two nodes for the performance profile
    log "Labeling -rt nodes"
    for w in ${testpmd_workers[@]}; do
      oc label node $w node-role.kubernetes.io/worker-rt="" --overwrite=true
    done
    # create the machineconfigpool
    log "Create the MCP"
    oc create -f machineconfigpool.yaml
    sleep 30
    if [ $? -ne 0 ] ; then
      log "Couldn't create the MCP, exiting!"
      exit 1
    fi
    # add the label to the MCP pool 
    log "Labeling the MCP"
    oc label mcp worker-rt machineconfiguration.openshift.io/role=worker-rt
    if [ $? -ne 0 ] ; then
      log "Couldn't label the MCP, exiting!"
      exit 1
    fi
    # apply the performanceProfile
    log "Applying the performanceProfile if it doesn't exist yet"
    profile=$(oc get performanceprofile benchmark-performance-profile-0 --no-headers)
    if [ $? -ne 0 ] ; then
      log "PerformanceProfile not found, creating it"
      oc create -f perf_profile.yaml
      if [ $? -ne 0 ] ; then
        log "Couldn't apply the performance profile, exiting!"
        exit 1
      fi
    fi
    # We need to wait for the nodes with the perfProfile applied to to reboot
    # this is a catchall approach, we sleep for 60 seconds and check the status of the nodes 
    # if they're ready we'll continue. Should the performance profile require reboots, that will have
    # started within the 60 seconds 
    log "Sleeping for 60 seconds"
    sleep 60
    readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
    while [[ $readycount -ne 2 ]]; do
      log "Waiting for -rt nodes to become ready again, sleeping 1 minute"
      sleep 60
      readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
    done
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
  log "Deploying cyclictest benchmark"
  envsubst < $CRD | oc apply -f -
  log "Sleeping for 60 seconds"
  sleep 60
}

check_logs_for_errors() {
client_pod=$(oc get pods -n benchmark-operator --no-headers | awk '{print $1}' | grep cyclictest | awk 'NR==1{print $1}')
if [ ! -z "$client_pod" ]; then
  num_critical=$(oc logs ${client_pod} -n benchmark-operator | grep CRITICAL | wc -l)
  if [ $num_critical -gt 3 ] ; then
    log "Encountered CRITICAL condition more than 3 times in cyclictest logs"
    log "Log dump of cyclictest pod"
    oc logs $client_pod -n benchmark-operator
    delete_benchmark
    exit 1
  fi
fi
}

wait_for_benchmark() {
  cyclictest_state=1
  for i in {1..480}; do # 2hours
    update
    if [ "${benchmark_state}" == "Error" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
    oc describe -n benchmark-operator benchmarks/cyclictest | grep State | grep Complete
    if [ $? -eq 0 ]; then
      log "cyclictest workload done!"
      cyclictest_state=$?
      break
    fi
    update
    log "Current status of the ${WORKLOAD} benchmark is ${uline}${benchmark_state}${normal}"
    check_logs_for_errors
    sleep 30
  done

  if [ "$cyclictest_state" == "1" ] ; then
    log "Workload failed"
    exit 1
  fi
}

assign_uuid() {
  update
  compare_testpmd_uuid=${benchmark_uuid}
  if [[ ${COMPARE} == "true" ]] ; then
    echo ${baseline_cyclictest_uuid},${compare_cyclictest_uuid} >> uuid.txt
  else
    echo ${compare_cyclictest_uuid} >> uuid.txt
  fi
}

run_benchmark_comparison() {
  log "Beginning benchmark comparison"
  ../../utils/touchstone-compare/run_compare.sh cyclictest ${baseline_cyclictest_uuid} ${compare_cyclictest_uuid} 
  log "Finished benchmark comparison"
  }

generate_csv() {
  log "Generating CSV"
  # tbd
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
  oc delete benchmarks.ripsaw.cloudbulldozer.io/cyclictest -n benchmark-operator
}

update() {
  benchmark_state=$(oc get benchmarks.ripsaw.cloudbulldozer.io/cyclictest -n benchmark-operator -o jsonpath='{.status.state}')
  benchmark_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/cyclictest -n benchmark-operator -o jsonpath='{.status.uuid}')
  benchmark_current_pair=$(oc get benchmarks.ripsaw.cloudbulldozer.io/cyclictest -n benchmark-operator -o jsonpath='{.spec.workload.args.pair}')
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
deploy_perf_profile
deploy_operator
deploy_workload
wait_for_benchmark
