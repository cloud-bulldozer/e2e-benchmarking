source env.sh
source ../../utils/benchmark-operator.sh

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
  oc get clusterversion
  if [ $? -ne 0 ]; then
    log "Workload Failed for cloud $cloud_name, Unable to connect to the cluster"
    exit 1
  fi
  cluster_version=$(oc get clusterversion --no-headers | awk '{ print $2 }')
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
  CRD=${CRD:-ripsaw-oslat-crd.yaml}
  export COMPARE=${COMPARE:=false}
  export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)

  cloud_name=$1
  if [ "$cloud_name" == "" ]; then
    export cloud_name="${network_type}_${platform}_${cluster_version}"
  fi

  if [[ ${COMPARE} == "true" ]]; then
    echo $BASELINE_CLOUD_NAME,$cloud_name > uuid.txt
  else
    echo $cloud_name > uuid.txt
  fi

  #Check to see if the infrastructure type is baremetal to adjust script as necessary 
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "BareMetal infastructure: setting isBareMetal accordingly"
    export isBareMetal=true
  else
    export isBareMetal=false
  fi

  if [[ "${isBareMetal}" == "true" ]]; then
     #Installing python3.8
     sudo yum -y install python3.8
     sudo alternatives --set python3 /usr/bin/python3.8
  fi
}

deploy_perf_profile() {
  if [[ $(oc get performanceprofile --no-headers | awk '{print $1}') == "benchmark-performance-profile-0" ]]; then
    log "Performance profile already exists. Applying the oslat profile"
    oc apply -f perf_profile.yaml
    if [ $? -ne 0 ]; then
      log "Couldn't apply performance profile, exiting!"
      exit 1
    fi
  else
    if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
      log "Trying to find a suitable node for oslat"
      # TODO: check if there are two -rt nodes already and use one of them
      # iterate over worker nodes bareMetalHandles until we have 2
      worker_count=0
      oslat_workers=()
      workers=$(oc get node -o name --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker= | head -${NODE_COUNT} | sed -e 's/^node\///')
      while [ $worker_count -lt 1 ]; do
        for worker in $workers; do
       	  worker_ip=$(oc get node $worker -o json | jq -r ".status.addresses[0].address" | grep 192 )
          if [[ ! -z "$worker_ip" ]]; then
            oslat_workers+=( $worker )
            ((worker_count=worker_count+1))
	    break
          fi
        done
      done
    fi
  fi
  # label the two nodes for the performance profile
  log "Labeling -lat nodes"
  for w in ${oslat_workers[@]}; do
    oc label node $w node-role.kubernetes.io/worker-rt="" --overwrite=true
  done
  # create the machineconfigpool
  log "Creating the MCP"
  oc apply -f machineconfigpool.yaml
  sleep 30
  if [ $? -ne 0 ] ; then
    log "Couldn't create the MCP, exiting!"
    exit 1
  fi
  # add the label to the MCP pool 
  log "Labeling the MCP"
  oc label mcp worker-rt machineconfiguration.openshift.io/role=worker-rt --overwrite=true
  if [ $? -ne 0 ] ; then
    log "Couldn't label the MCP, exiting!"
    exit 1
  fi
  # apply the performanceProfile
  log "Applying the performanceProfile since it doesn't exist yet"
  profile=$(oc get performanceprofile benchmark-performance-profile-0 --no-headers)
  if [ $? -ne 0 ] ; then
    log "PerformanceProfile not found, creating it"
    oc apply -f perf_profile.yaml
    if [ $? -ne 0 ] ; then
      log "Couldn't apply the performance profile, exiting!"
      exit 1
    fi
  fi
  # We need to wait for the nodes with the perfProfile applied to to reboot
  # this is a catchall approach, we sleep for 60 seconds and check the status of the nodes
  # if they're ready we'll continue. Should the performance profile require reboots, that will have
  # started within the 60 seconds
  iterations=0
  log "Sleeping for 60 seconds"
  sleep 60
  readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  while [[ $readycount -lt 1 ]]; do
    if [[ $iterations -gt $PROFILE_TIMEOUT ]]; then
      log "Waited for the -rt MCP for $PROFILE_TIMEOUT minutes, bailing!"
      exit 124
    fi
    log "Waiting for -rt nodes to become ready again, sleeping 1 minute"
    sleep 60
    readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
    iterations=$((iterations+1))
  done
}

deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
}

check_logs_for_errors() {
client_pod=$(oc get pods -n benchmark-operator --no-headers | grep -i running | awk '{print $1}' | grep oslat | awk 'NR==1{print $1}')
if [ ! -z "$client_pod" ]; then
  num_critical=$(oc logs ${client_pod} -n benchmark-operator | grep CRITICAL | wc -l)
  if [ $num_critical -gt 3 ] ; then
    log "Encountered CRITICAL condition more than 3 times in oslat pod logs"
    log "Log dump of oslat pod"
    oc logs $client_pod -n benchmark-operator
    delete_benchmark
    exit 1
  fi
fi
}

wait_for_benchmark() {
  oslat_state=1
  for i in {1..480}; do # 2hours
    update
    if [ "${benchmark_state}" == "Error" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
    oc describe -n benchmark-operator benchmarks/oslat-$UUID | grep State | grep Complete
    if [ $? -eq 0 ]; then
      log "oslat workload done!"
      oslat_state=$?
      break
    fi
    update
    log "Current status of the oslat ${WORKLOAD} benchmark is ${uline}${benchmark_state}${normal}"
    check_logs_for_errors
    sleep 30
  done

  if [ "$oslat_state" == "1" ] ; then
    log "Workload failed"
    exit 1
  fi
}

assign_uuid() {
  update
  compare_testpmd_uuid=${benchmark_uuid}
  if [[ ${COMPARE} == "true" ]] ; then
    echo ${baseline_testpmd_uuid},${compare_testpmd_uuid} >> uuid.txt
  else
    echo ${compare_testpmd_uuid} >> uuid.txt
  fi
}

run_benchmark_comparison() {
  log "Beginning benchmark comparison"
  ../../utils/touchstone-compare/run_compare.sh testpmd ${baseline_testpmd_uuid} ${compare_testpmd_uuid}
  log "Finished benchmark comparison"
  }

generate_csv() {
  log "Generating CSV"
  # tbd
}

delete_benchmark() {
  oc delete benchmarks.ripsaw.cloudbulldozer.io/oslat -n benchmark-operator
}

update() {
  benchmark_state=$(oc get benchmarks.ripsaw.cloudbulldozer.io/oslat -n benchmark-operator -o jsonpath='{.status.state}')
  benchmark_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/oslat -n benchmark-operator -o jsonpath='{.status.uuid}')
  benchmark_current_pair=$(oc get benchmarks.ripsaw.cloudbulldozer.io/oslat -n benchmark-operator -o jsonpath='{.spec.workload.args.pair}')
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
check_cluster_health
deploy_perf_profile
deploy_operator
run_workload ripsaw-oslat-crd.yaml
